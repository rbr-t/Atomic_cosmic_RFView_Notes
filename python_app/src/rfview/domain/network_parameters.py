"""Two-port conversions for a common, real, positive reference impedance."""

import math
from collections.abc import Sequence
from typing import Literal

from rfview.domain.models import positive

Matrix2 = tuple[tuple[complex, complex], tuple[complex, complex]]
SINGULARITY_THRESHOLD = 1e-15


def validated_matrix(s: Sequence[Sequence[complex]]) -> Matrix2:
    if len(s) != 2 or any(len(row) != 2 for row in s):
        raise ValueError("Requires a 2x2 S-matrix in row/column order")
    for row in s:
        for value in row:
            if isinstance(value, bool) or not isinstance(value, (complex, int, float)):
                raise ValueError("S-matrix entries must be finite numeric values")
            if not math.isfinite(value.real) or not math.isfinite(value.imag):
                raise ValueError("S-matrix entries must be finite numeric values")
    return (
        (complex(s[0][0]), complex(s[0][1])),
        (complex(s[1][0]), complex(s[1][1])),
    )


def _convert(s: Sequence[Sequence[complex]], z0: float, target: Literal["Z", "Y"]) -> Matrix2:
    if isinstance(z0, bool):
        raise ValueError("Reference impedance must be a positive real number")
    positive(z0, "reference impedance (ohm)")
    s = validated_matrix(s)
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


def _finite_matrix(result: Matrix2, name: str) -> Matrix2:
    if any(
        not math.isfinite(value.real) or not math.isfinite(value.imag)
        for row in result
        for value in row
    ):
        raise ValueError(f"S-to-{name} result exceeds numeric range")
    return result


def s_to_h(s: Sequence[Sequence[complex]], z0: float = 50) -> Matrix2:
    """Hybrid parameters: h11 ohms, h22 siemens; h12/h21 dimensionless."""
    z = s_to_z(s, z0)
    a, b = z[0]
    c, d = z[1]
    if abs(d) < SINGULARITY_THRESHOLD:
        raise ValueError("S-to-h conversion is singular or near-singular (Z22)")
    return _finite_matrix((((a * d - b * c) / d, b / d), (-c / d, 1 / d)), "h")


def s_to_abcd(s: Sequence[Sequence[complex]], z0: float = 50) -> Matrix2:
    """Chain convention [V1,I1] = ABCD [V2,-I2]; B ohms, C siemens."""
    if isinstance(z0, bool):
        raise ValueError("Reference impedance must be a positive real number")
    positive(z0, "reference impedance (ohm)")
    matrix = validated_matrix(s)
    a, b = matrix[0]
    c, d = matrix[1]
    denominator = 2 * c
    if not math.isfinite(denominator.real) or not math.isfinite(denominator.imag):
        raise ValueError("S-to-ABCD denominator exceeds numeric range")
    if abs(denominator) < SINGULARITY_THRESHOLD:
        raise ValueError("S-to-ABCD conversion is singular or near-singular (2*S21)")
    return _finite_matrix(
        (
            (
                ((1 + a) * (1 - d) + b * c) / denominator,
                z0 * ((1 + a) * (1 + d) - b * c) / denominator,
            ),
            (
                ((1 - a) * (1 - d) - b * c) / denominator / z0,
                ((1 - a) * (1 + d) + b * c) / denominator,
            ),
        ),
        "ABCD",
    )


def s_to_t(s: Sequence[Sequence[complex]]) -> Matrix2:
    """Scattering transfer, not ABCD: [b1,a1] = T [a2,b2]."""
    matrix = validated_matrix(s)
    a, b = matrix[0]
    c, d = matrix[1]
    if abs(c) < SINGULARITY_THRESHOLD:
        raise ValueError("S-to-T conversion is singular or near-singular (S21)")
    return _finite_matrix((((b * c - a * d) / c, a / c), (-d / c, 1 / c)), "T")
