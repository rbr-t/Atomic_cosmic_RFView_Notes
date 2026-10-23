"""Two-port conversions for a common, real, positive reference impedance."""

import math
from collections.abc import Sequence
from typing import Literal

from rfview.domain.models import positive

Matrix2 = tuple[tuple[complex, complex], tuple[complex, complex]]
SINGULARITY_THRESHOLD = 1e-15


def _convert(s: Sequence[Sequence[complex]], z0: float, target: Literal["Z", "Y"]) -> Matrix2:
    if isinstance(z0, bool):
        raise ValueError("Reference impedance must be a positive real number")
    positive(z0, "reference impedance (ohm)")
    if len(s) != 2 or any(len(row) != 2 for row in s):
        raise ValueError("Conversion requires a 2x2 S-matrix in row/column order")
    for row in s:
        for value in row:
            if isinstance(value, bool) or not isinstance(value, (complex, int, float)):
                raise ValueError("S-matrix entries must be finite numeric values")
            if not math.isfinite(value.real) or not math.isfinite(value.imag):
                raise ValueError("S-matrix entries must be finite numeric values")
    a, b = complex(s[0][0]), complex(s[0][1])
    c, d = complex(s[1][0]), complex(s[1][1])
    sign = -1 if target == "Z" else 1
    determinant = (1 + sign * a) * (1 + sign * d) - b * c
    if not math.isfinite(determinant.real) or not math.isfinite(determinant.imag):
        raise ValueError(f"S-to-{target} determinant exceeds numeric range")
    if abs(determinant) < SINGULARITY_THRESHOLD:
        raise ValueError(
            f"S-to-{target} conversion is singular or near-singular "
            f"(|determinant| < {SINGULARITY_THRESHOLD:g})"
        )
    scale = z0 if target == "Z" else 1 / z0
    result: Matrix2 = (
        (
            scale * ((1 - sign * a) * (1 + sign * d) + b * c) / determinant,
            scale * (-sign * 2 * b) / determinant,
        ),
        (
            scale * (-sign * 2 * c) / determinant,
            scale * ((1 + sign * a) * (1 - sign * d) + b * c) / determinant,
        ),
    )
    if any(
        not math.isfinite(value.real) or not math.isfinite(value.imag)
        for row in result
        for value in row
    ):
        raise ValueError(f"S-to-{target} result exceeds numeric range")
    return result


def s_to_z(s: Sequence[Sequence[complex]], z0: float = 50) -> Matrix2:
    """Return row-major Z parameters in ohms, using the legacy determinant threshold."""
    return _convert(s, z0, "Z")


def s_to_y(s: Sequence[Sequence[complex]], z0: float = 50) -> Matrix2:
    """Return row-major Y parameters in siemens, using the legacy determinant threshold."""
    return _convert(s, z0, "Y")
