"""Explicit legacy-compatible two-port stability and gain estimates."""

import math
from collections.abc import Sequence
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from rfview.domain.network_parameters import SINGULARITY_THRESHOLD, validated_matrix


class StabilityMetrics(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    model_version: Literal["legacy-r-stability-v1"] = "legacy-r-stability-v1"
    delta_mag: float
    K: float | None
    mu_in: float | None
    mu_out: float | None
    B1: float
    msg_db: float | None
    mag_db: float | None
    stable: bool
    warnings: list[str] = Field(default_factory=list)


class StabilityCircle(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    center_r: float
    center_i: float
    radius: float = Field(ge=0)


class StabilityCircles(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    model_version: Literal["legacy-r-stability-circles-v1"] = "legacy-r-stability-circles-v1"
    load: StabilityCircle | None
    source: StabilityCircle | None
    warnings: tuple[str, ...]


class PowerGainEstimates(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    model_version: Literal["conventional-power-gain-v2"] = "conventional-power-gain-v2"
    msg_db: float | None
    mag_db: float | None
    warnings: tuple[str, ...]


def power_gain_estimates(s: Sequence[Sequence[complex]]) -> PowerGainEstimates:
    """Power gains in dB, with MAG only in the unconditionally stable region."""
    matrix = validated_matrix(s)
    metrics = stability_metrics(matrix)
    reverse, forward = abs(matrix[0][1]), abs(matrix[1][0])
    warnings = [
        "Conventional power-gain version uses 10*log10, not the legacy 20*log10 scale.",
        "MSG is the |S21/S12| expression, not guaranteed attainable gain. "
        "MAG is shown only for K>1 and |Delta|<1; no stability certification.",
    ]
    msg = mag = None
    if reverse > SINGULARITY_THRESHOLD and forward > 0:
        msg = 10 * (math.log10(forward) - math.log10(reverse))
        if metrics.K is not None and metrics.K > 1 and metrics.delta_mag < 1:
            k = metrics.K
            factor = (1 / k) / (1 + math.sqrt(max(0, 1 - (1 / k) ** 2)))
            if factor > 0:
                mag = msg + 10 * math.log10(factor)
    if msg is None:
        warnings.append("MSG/MAG undefined for zero forward or negligible reverse transmission.")
    elif mag is None:
        warnings.append("MAG unavailable outside its supported stable-region/numeric conditions.")
    return PowerGainEstimates(msg_db=msg, mag_db=mag, warnings=tuple(warnings))


def stability_circles(s: Sequence[Sequence[complex]]) -> StabilityCircles:
    """Return load/source reflection-plane boundaries, not stable-side classifications."""
    matrix = validated_matrix(s)
    s11, s12 = matrix[0]
    s21, s22 = matrix[1]
    try:
        delta = s11 * s22 - s12 * s21
        delta_squared = abs(delta) ** 2
        product = abs(s12 * s21)
        warnings = [
            "Circle boundaries alone do not identify the stable side or certify stability.",
            "A zero-radius circle can be a degenerate boundary, not a stability guarantee.",
        ]

        def circle(
            port: Literal["Load", "Source"], reflection: complex, opposite: complex
        ) -> StabilityCircle | None:
            denominator = abs(reflection) ** 2 - delta_squared
            numerator = (reflection - delta * opposite.conjugate()).conjugate()
            if not all(
                math.isfinite(value)
                for value in (
                    denominator,
                    numerator.real,
                    numerator.imag,
                    product,
                )
            ):
                raise ValueError("Stability circle calculation exceeds numeric range")
            if abs(denominator) <= SINGULARITY_THRESHOLD:
                warnings.append(
                    f"{port} circle is undefined at |denominator| <= 1e-15; "
                    "a line/degenerate boundary is not represented as a finite circle."
                )
                return None
            center = numerator / denominator
            radius = product / abs(denominator)
            if not all(math.isfinite(value) for value in (center.real, center.imag, radius)):
                raise ValueError("Stability circle calculation exceeds numeric range")
            return StabilityCircle(center_r=center.real, center_i=center.imag, radius=radius)

        load = circle("Load", s22, s11)
        source = circle("Source", s11, s22)
        return StabilityCircles(load=load, source=source, warnings=tuple(warnings))
    except OverflowError as exc:
        raise ValueError("Stability circle calculation exceeds numeric range") from exc


def stability_metrics(s: Sequence[Sequence[complex]]) -> StabilityMetrics:
    matrix = validated_matrix(s)
    s11, s12 = matrix[0]
    s21, s22 = matrix[1]
    try:
        delta = s11 * s22 - s12 * s21
        dm = abs(delta)
        a, d, product = abs(s11), abs(s22), abs(s12 * s21)
        numerator = 1 - a**2 - d**2 + dm**2
        b1 = 1 + a**2 - d**2 - dm**2
        den_in = abs(s22 - delta * s11.conjugate()) + product
        den_out = abs(s11 - delta * s22.conjugate()) + product
        intermediates = (dm, product, numerator, b1, den_in, den_out)
        if not all(math.isfinite(value) for value in intermediates):
            raise ValueError("Stability calculation exceeds numeric range")
        warnings = [
            "Legacy gain estimates use 20*log10 of the power-gain ratio, "
            "not the conventional 10*log10; do not treat MSG/MAG as corrected power gain.",
            "Legacy stable flag uses K>1 and mu_in>1, not a full stability certification.",
        ]
        k = numerator / (2 * product) if product > SINGULARITY_THRESHOLD else None
        if k is None:
            warnings.append("K is unbounded/undefined at negligible S12*S21; legacy R returns Inf.")
        mu_in = (1 - a**2) / den_in if den_in > SINGULARITY_THRESHOLD else None
        mu_out = (1 - d**2) / den_out if den_out > SINGULARITY_THRESHOLD else None
        if mu_in is None or mu_out is None:
            warnings.append("A mu denominator is negligible; that metric is undefined.")
        msg = (
            20 * (math.log10(max(abs(s21), 1e-15)) - math.log10(abs(s12)))
            if abs(s12) > SINGULARITY_THRESHOLD
            else None
        )
        mag = None
        if k is not None and k >= 1 and msg is not None:
            # Reciprocal form avoids cancellation in K-sqrt(K^2-1).
            root = k * math.sqrt(max(1 - (1 / k) ** 2, 0))
            factor = (1 / k) / (1 + root / k)
            mag = msg + 20 * math.log10(max(factor, 1e-15))
        if msg is None:
            warnings.append("Legacy MSG/MAG are undefined for negligible reverse transmission.")
        elif mag is None:
            warnings.append("MAG is undefined because K is unavailable or below one.")
        # R treats negligible coupling as K=Inf when evaluating the legacy flag.
        stable = (k is None or k > 1) and mu_in is not None and mu_in > 1
        return StabilityMetrics(
            delta_mag=dm,
            K=k,
            mu_in=mu_in,
            mu_out=mu_out,
            B1=b1,
            msg_db=msg,
            mag_db=mag,
            stable=stable,
            warnings=warnings,
        )
    except OverflowError as exc:
        raise ValueError("Stability calculation exceeds numeric range") from exc
