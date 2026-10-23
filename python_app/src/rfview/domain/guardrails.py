from __future__ import annotations

import math
from typing import Literal, TypedDict

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
    ft_ghz_max: float | None = Field(default=None, gt=0)
    fmax_ghz_max: float | None = Field(default=None, gt=0)


class PaeLimits(GuardrailModel):
    max_practical_p3db: float = Field(default=78.5, ge=0, le=100)
    typical_p3db: float | None = Field(default=None, ge=0, le=100)


class VoltageLimits(GuardrailModel):
    typical: float = Field(gt=0)
    max_abs: float | None = Field(default=None, gt=0)


class DensityLimits(GuardrailModel):
    max: float = Field(default=999, gt=0)
    min: float | None = Field(default=None, ge=0)
    typical: float | None = Field(default=None, gt=0)


class ThermalLimits(GuardrailModel):
    max_tj_c: float | None = Field(default=None, gt=-273.15)


class TechnologyGuardrail(GuardrailModel):
    label: str = Field(min_length=1)
    color: str = Field(default="#888888", pattern=r"^#[0-9a-fA-F]{6}$")
    freq_range_ghz: FrequencyRange
    gain_db: GainLimits
    pae_pct: PaeLimits
    vdd: VoltageLimits
    pout_density_w_per_mm: DensityLimits
    thermal: ThermalLimits = Field(default_factory=ThermalLimits)


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


class DesignSpaceRow(TypedDict):
    tech: str
    label: str
    color: str
    freq_ghz: float
    gain_db: float
    pout_density_typ: float
    pout_density_max: float
    pae_typ_pct: float
    pae_max_pct: float
    vdd_typ: float
    in_sweet_spot: bool


class GainBandwidthRow(TypedDict):
    tech: str
    label: str
    color: str
    freq_ghz: float
    gain_typ: float
    gain_max: float
    in_range: bool


class PaeBackoffRow(TypedDict):
    tech: str
    label: str
    tech_label: str
    color: str
    pa_class: str
    backoff_db: float
    pae_pct: float


GuardrailSummaryRow = TypedDict(
    "GuardrailSummaryRow",
    {
        "Technology": str,
        "Freq Range (GHz)": str,
        "Sweet Spot (GHz)": str,
        "fT typ (GHz)": float,
        "fmax typ (GHz)": float | None,
        "Vdd typ (V)": float,
        "Vdd max (V)": float | None,
        "Pout density W/mm": str,
        "PAE P3dB typ (%)": float | None,
        "PAE P3dB max (%)": float | None,
        "Max Tj (\u00b0C)": float | None,
    },
)


def _logspace(start: float, stop: float, count: int) -> list[float]:
    first, last = math.log(start), math.log(stop)
    return [math.exp(first + (last - first) * index / (count - 1)) for index in range(count)]


def build_design_space_data(
    catalog: GuardrailCatalog, freq_points: int = 60
) -> list[DesignSpaceRow]:
    if isinstance(freq_points, bool) or not isinstance(freq_points, int) or freq_points < 1:
        raise ValueError("freq_points must be a positive integer")
    rows: list[DesignSpaceRow] = []
    for key, tech in catalog.technologies.items():
        fr, gd, pd, pae = (
            tech.freq_range_ghz,
            tech.gain_db,
            tech.pout_density_w_per_mm,
            tech.pae_pct,
        )
        freqs = (
            [math.exp(math.log(fr.min))]
            if freq_points == 1
            else _logspace(fr.min, fr.max, freq_points)
        )
        for freq in freqs:
            scale = min((gd.ft_ghz_typical / freq) ** 0.08, 1)
            rows.append(
                DesignSpaceRow(
                    tech=key,
                    label=tech.label,
                    color=tech.color,
                    freq_ghz=freq,
                    gain_db=available_gain(freq, gd.ft_ghz_typical, gd.fmax_ghz_typical),
                    pout_density_typ=pd.typical if pd.typical is not None else 1,
                    pout_density_max=pd.max if "max" in pd.model_fields_set else 2,
                    pae_typ_pct=(pae.typical_p3db if pae.typical_p3db is not None else 45) * scale,
                    pae_max_pct=(
                        pae.max_practical_p3db
                        if "max_practical_p3db" in pae.model_fields_set
                        else 65
                    )
                    * scale,
                    vdd_typ=tech.vdd.typical,
                    in_sweet_spot=fr.sweet_spot_min <= freq <= fr.sweet_spot_max,
                )
            )
    return rows


def build_gain_bandwidth_data(catalog: GuardrailCatalog) -> list[GainBandwidthRow]:
    rows: list[GainBandwidthRow] = []
    freqs = _logspace(0.1, 300, 200)
    for key, tech in catalog.technologies.items():
        fr, gd = tech.freq_range_ghz, tech.gain_db
        ft = gd.ft_ghz_typical
        fmax = gd.fmax_ghz_typical if gd.fmax_ghz_typical is not None else ft * 2.2
        ftx = gd.ft_ghz_max if gd.ft_ghz_max is not None else ft * 1.3
        fmxx = gd.fmax_ghz_max if gd.fmax_ghz_max is not None else fmax * 1.3
        for freq in freqs:
            if not fr.min * 0.5 <= freq <= fr.max * 2:
                continue
            rows.append(
                GainBandwidthRow(
                    tech=key,
                    label=tech.label,
                    color=tech.color,
                    freq_ghz=freq,
                    gain_typ=available_gain(freq, ft, fmax),
                    gain_max=available_gain(freq, ftx, fmxx),
                    in_range=fr.min <= freq <= fr.max,
                )
            )
    return rows


def build_pae_backoff_data(catalog: GuardrailCatalog) -> list[PaeBackoffRow]:
    rows: list[PaeBackoffRow] = []
    for key, tech in catalog.technologies.items():
        pae = tech.pae_pct.typical_p3db
        for pa_class in ("A", "AB", "B", "Doherty", "F"):
            for index in range(65):
                backoff = index / 4
                rows.append(
                    PaeBackoffRow(
                        tech=key,
                        label=f"{tech.label} - {pa_class}",
                        tech_label=tech.label,
                        color=tech.color,
                        pa_class=pa_class,
                        backoff_db=backoff,
                        pae_pct=pae_backoff(pae if pae is not None else 45, backoff, pa_class),
                    )
                )
    return rows


def build_guardrail_summary_table(catalog: GuardrailCatalog) -> list[GuardrailSummaryRow]:
    rows: list[GuardrailSummaryRow] = []
    for tech in catalog.technologies.values():
        fr, pd, pae = tech.freq_range_ghz, tech.pout_density_w_per_mm, tech.pae_pct
        rows.append(
            {
                "Technology": tech.label,
                "Freq Range (GHz)": f"{fr.min:.1f} \u2013 {fr.max:.1f}",
                "Sweet Spot (GHz)": f"{fr.sweet_spot_min:.1f} \u2013 {fr.sweet_spot_max:.1f}",
                "fT typ (GHz)": tech.gain_db.ft_ghz_typical,
                "fmax typ (GHz)": tech.gain_db.fmax_ghz_typical,
                "Vdd typ (V)": tech.vdd.typical,
                "Vdd max (V)": tech.vdd.max_abs,
                "Pout density W/mm": (
                    f"{pd.min if pd.min is not None else 0:.2f} \u2013 "
                    f"{pd.max if 'max' in pd.model_fields_set else 0:.2f}"
                ),
                "PAE P3dB typ (%)": pae.typical_p3db,
                "PAE P3dB max (%)": (
                    pae.max_practical_p3db if "max_practical_p3db" in pae.model_fields_set else None
                ),
                "Max Tj (\u00b0C)": tech.thermal.max_tj_c,
            }
        )
    return rows
