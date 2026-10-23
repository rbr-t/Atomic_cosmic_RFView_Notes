"""Explicitly versioned generic lifetime hypothesis; not a device qualification model."""

import math
from collections.abc import Sequence
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from rfview.domain.models import nonnegative, positive


class LifetimeInputs(BaseModel):
    model_config = ConfigDict(frozen=True, strict=True, allow_inf_nan=False, extra="forbid")

    tj_c: float = Field(gt=-273.15)
    reference_c: float = Field(default=125, gt=-273.15)
    base_hours: float = Field(default=1e6, gt=0)
    activation_ev: float = Field(default=0.7, ge=0)
    voltage_stress: float = Field(default=1, gt=0)
    current_stress: float = Field(default=1, gt=0)


class LifetimeEstimate(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    model_version: Literal["arrhenius-lifetime-v2"] = "arrhenius-lifetime-v2"
    inputs: LifetimeInputs
    mttf_hours: float = Field(gt=0)
    mttf_years: float = Field(gt=0)
    failure_rate_per_hour: float = Field(gt=0)
    warnings: tuple[str, ...]


def lifetime_estimate(inputs: LifetimeInputs) -> LifetimeEstimate:
    """Correct thermal acceleration direction; retain assumed squared stress factors."""
    log_acceleration = (
        (inputs.activation_ev / 8.617e-5)
        * (1 / (inputs.reference_c + 273.15) - 1 / (inputs.tj_c + 273.15))
        + 2 * math.log(inputs.voltage_stress)
        + 2 * math.log(inputs.current_stress)
    )
    try:
        hours = math.exp(math.log(inputs.base_hours) - log_acceleration)
        if not math.isfinite(hours) or hours <= 0 or not math.isfinite(1 / hours):
            raise ValueError("Lifetime estimate exceeds numeric range")
        return LifetimeEstimate(
            inputs=inputs,
            mttf_hours=hours,
            mttf_years=hours / 8760,
            failure_rate_per_hour=1 / hours,
            warnings=(
                "Generic constant-hazard/squared-stress hypothesis, not vendor-calibrated "
                "lifetime prediction or safety certification.",
                "Version v2 divides by thermal acceleration. Legacy R incorrectly "
                "multiplies it, increasing lifetime with increasing junction temperature.",
                "Base lifetime, reference conditions and activation energy require "
                "engineering justification for the actual device and failure mechanism.",
            ),
        )
    except OverflowError as exc:
        raise ValueError("Lifetime estimate exceeds numeric range") from exc


def reliability_curve(
    time_hours: Sequence[float], mttf_hours: float
) -> tuple[tuple[float, float], ...]:
    positive(mttf_hours, "MTTF (hours)")
    if not 1 <= len(time_hours) <= 10_000:
        raise ValueError("Reliability curves require 1-10000 time points")
    result = []
    previous = -1.0
    for value in time_hours:
        if isinstance(value, bool):
            raise ValueError("Time values must be numeric hours, not booleans")
        nonnegative(value, "time (hours)")
        if value <= previous:
            raise ValueError("Time points must be strictly increasing")
        result.append((value, 100 * math.exp(-value / mttf_hours)))
        previous = value
    return tuple(result)
