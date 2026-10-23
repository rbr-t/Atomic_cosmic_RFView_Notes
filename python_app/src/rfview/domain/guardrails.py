from __future__ import annotations

import math
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from rfview.domain.models import finite, nonnegative, positive


class GuardrailModel(BaseModel):
    model_config = ConfigDict(extra="allow", allow_inf_nan=False)


class FrequencyRange(GuardrailModel):
    min: float = Field(gt=0)
    max: float = Field(gt=0)
    sweet_spot_min: float
    sweet_spot_max: float

    @model_validator(mode="after")
    def ordered(self) -> FrequencyRange:
        if not self.min <= self.sweet_spot_min <= self.sweet_spot_max <= self.max:
            raise ValueError("Frequency sweet spot must lie within the ordered operating range")
        return self


class GainLimits(GuardrailModel):
    ft_ghz_typical: float = Field(gt=0)
    fmax_ghz_typical: float | None = Field(default=None, gt=0)


class PaeLimits(GuardrailModel):
    max_practical_p3db: float = Field(default=78.5, ge=0, le=100)


class VoltageLimits(GuardrailModel):
    typical: float = Field(gt=0)
    max_abs: float | None = Field(default=None, gt=0)


class DensityLimits(GuardrailModel):
    max: float = Field(default=999, gt=0)


class TechnologyGuardrail(GuardrailModel):
    label: str = Field(min_length=1)
    freq_range_ghz: FrequencyRange
    gain_db: GainLimits
    pae_pct: PaeLimits
    vdd: VoltageLimits
    pout_density_w_per_mm: DensityLimits


class GainRule(GuardrailModel):
    margin_db: float = Field(default=3, ge=0)
    error_margin_db: float = Field(default=6, ge=0)

    @model_validator(mode="after")
    def ordered(self) -> GainRule:
        if self.error_margin_db < self.margin_db:
            raise ValueError("Gain error margin must not be below the warning margin")
        return self


class PaeRule(GuardrailModel):
    error_threshold_pct: float = Field(default=80, ge=0, le=100)


class DensityRule(GuardrailModel):
    warning_margin_pct: float = Field(default=10, ge=0, le=100)


class ValidationRules(GuardrailModel):
    gain_vs_freq: GainRule = Field(default_factory=GainRule)
    pae_sanity: PaeRule = Field(default_factory=PaeRule)
    pout_density: DensityRule = Field(default_factory=DensityRule)


class GuardrailCatalog(GuardrailModel):
    technologies: dict[str, TechnologyGuardrail] = Field(min_length=1)
    validation_rules: ValidationRules = Field(default_factory=ValidationRules)


class DeviceParameters(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False, strict=True)

    tech_key: str
    freq_ghz: float = Field(gt=0)
    gain_db: float
    pae_pct: float = Field(ge=0, le=100)
    pout_dbm: float
    vdd: float = Field(gt=0)
    pout_density: float | None = Field(default=None, ge=0)


class DeviceValidation(BaseModel):
    model_version: Literal["legacy-r-guardrails-v1"] = "legacy-r-guardrails-v1"
    status: Literal["ok", "warning", "error"]
    errors: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    tech: str
    freq_ghz: float
    max_gain_available: float
    pae_max_practical: float


def validate_device_params(device: DeviceParameters, catalog: GuardrailCatalog) -> DeviceValidation:
    if device.tech_key not in catalog.technologies:
        raise ValueError(f"Unknown technology: {device.tech_key}")
    tech = catalog.technologies[device.tech_key]
    rules = catalog.validation_rules
    errors: list[str] = []
    warnings: list[str] = []
    fr = tech.freq_range_ghz
    if not fr.min <= device.freq_ghz <= fr.max:
        errors.append(
            f"Frequency {device.freq_ghz:.1f} GHz is outside {tech.label} operating range "
            f"({fr.min:.1f}-{fr.max:.1f} GHz)"
        )
    elif not fr.sweet_spot_min <= device.freq_ghz <= fr.sweet_spot_max:
        warnings.append(
            f"{device.freq_ghz:.1f} GHz is outside the sweet spot "
            f"({fr.sweet_spot_min:.1f}-{fr.sweet_spot_max:.1f} GHz) for {tech.label}"
        )
    gain = available_gain(
        device.freq_ghz, tech.gain_db.ft_ghz_typical, tech.gain_db.fmax_ghz_typical
    )
    if device.gain_db > gain + rules.gain_vs_freq.error_margin_db:
        errors.append(
            f"Gain {device.gain_db:.1f} dB exceeds the legacy fT/f model limit "
            f"for {tech.label} at {device.freq_ghz:.1f} GHz "
            f"(available gain {gain:.1f} dB)"
        )
    elif device.gain_db > gain + rules.gain_vs_freq.margin_db:
        warnings.append(
            f"Gain {device.gain_db:.1f} dB is aggressive for {tech.label} "
            f"(available gain {gain:.1f} dB)"
        )
    pae_max = tech.pae_pct.max_practical_p3db
    if device.pae_pct > rules.pae_sanity.error_threshold_pct:
        errors.append(
            f"PAE {device.pae_pct:.1f}% exceeds the configured legacy threshold "
            f"({rules.pae_sanity.error_threshold_pct:.1f}%)"
        )
    elif device.pae_pct > pae_max:
        warnings.append(
            f"PAE {device.pae_pct:.1f}% exceeds reported best practice "
            f"for {tech.label} (typical max {pae_max:.1f}%)"
        )
    max_voltage = tech.vdd.max_abs if tech.vdd.max_abs is not None else tech.vdd.typical * 2
    if device.vdd > max_voltage:
        errors.append(
            f"Vdd {device.vdd:.1f} V exceeds absolute maximum {max_voltage:.1f} V for {tech.label}"
        )
    if device.pout_density is not None:
        maximum = tech.pout_density_w_per_mm.max
        warning = maximum * (1 - rules.pout_density.warning_margin_pct / 100)
        if device.pout_density > maximum:
            errors.append(
                f"Pout density {device.pout_density:.2f} W/mm exceeds process maximum "
                f"{maximum:.2f} W/mm for {tech.label}"
            )
        elif device.pout_density > warning:
            warnings.append(
                f"Pout density {device.pout_density:.2f} W/mm is near the process limit "
                f"({maximum:.2f} W/mm) for {tech.label}"
            )
    return DeviceValidation(
        status="error" if errors else "warning" if warnings else "ok",
        errors=errors,
        warnings=warnings,
        tech=tech.label,
        freq_ghz=device.freq_ghz,
        max_gain_available=round(gain, 1),
        pae_max_practical=pae_max,
    )


def available_gain(freq_ghz: float, ft_ghz: float, fmax_ghz: float | None = None) -> float:
    nonnegative(freq_ghz, "frequency (GHz)")
    positive(ft_ghz, "fT (GHz)")
    fmax = ft_ghz * 2.2 if fmax_ghz is None else positive(fmax_ghz, "fmax (GHz)")
    freq = max(freq_ghz, 0.001)
    limit = fmax if freq < ft_ghz / 3 else ft_ghz
    return min(max(20 * math.log10(max(limit / freq, 1)) - 3, 0), 33)


def pae_backoff(pae_p3db_pct: float, backoff_db: float, pa_class: str = "AB") -> float:
    finite(pae_p3db_pct, "PAE (%)")
    if not 0 <= pae_p3db_pct <= 100:
        raise ValueError("PAE must be in [0, 100] %")
    nonnegative(backoff_db, "backoff (dB)")
    ratio = 10 ** (-backoff_db / 10)
    if pa_class == "Doherty":
        scale = 1 if backoff_db <= 6 else math.sqrt(ratio / 10 ** (-6 / 10))
    else:
        exponent = {
            "A": 1,
            "B": 0.5,
            "AB": 0.6,
            "E": 0.3 if backoff_db <= 4 else 0.55,
            "F": 0.25 if backoff_db <= 4 else 0.50,
        }
        if pa_class not in exponent:
            raise ValueError(f"Unsupported PA class: {pa_class}")
        scale = ratio ** exponent[pa_class]
    return max(pae_p3db_pct * scale, 1)
