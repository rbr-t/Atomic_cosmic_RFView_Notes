import cmath
import hashlib
import json
from pathlib import Path

import pytest

from rfview.domain.stability import stability_circles

REFERENCE = json.loads(
    (Path(__file__).parent / "fixtures" / "stability_circles_reference.json").read_text(
        encoding="utf-8"
    )
)


@pytest.mark.parametrize("case", REFERENCE["cases"], ids=lambda case: case["name"])
def test_r_reference_circles(case: dict) -> None:
    matrix = [[complex(v["real"], v["imag"]) for v in row] for row in case["s"]]
    before = [row[:] for row in matrix]
    result = stability_circles(matrix)
    for port in ("load", "source"):
        actual = getattr(result, port)
        expected = case["expected"][port]
        if expected is None:
            assert actual is None
            assert any(port.capitalize() in warning for warning in result.warnings)
        else:
            assert actual is not None
            for key, value in expected.items():
                assert getattr(actual, key) == pytest.approx(value, rel=1e-10, abs=1e-12)
    assert matrix == before
    json.dumps(result.model_dump(), allow_nan=False)


@pytest.mark.parametrize("port", ["load", "source"])
def test_circle_points_satisfy_unit_reflection_boundary(port: str) -> None:
    s11, s12, s21, s22 = 0.1 + 0.2j, 0.3 + 0.4j, 2 - 0.5j, -0.2 + 0.1j
    result = stability_circles(((s11, s12), (s21, s22)))
    circle = getattr(result, port)
    assert circle is not None
    center = complex(circle.center_r, circle.center_i)
    for index in range(16):
        gamma = center + circle.radius * cmath.exp(2j * cmath.pi * index / 16)
        reflection = (
            s11 + s12 * s21 * gamma / (1 - s22 * gamma)
            if port == "load"
            else s22 + s12 * s21 * gamma / (1 - s11 * gamma)
        )
        assert abs(reflection) == pytest.approx(1, rel=1e-12, abs=1e-12)


def test_known_bilateral_circle_and_independent_undefined_ports() -> None:
    result = stability_circles(((0, 0.1), (2, 0)))
    assert result.load is not None and result.source is not None
    assert result.load.center_r == 0 and result.load.center_i == 0
    assert result.load.radius == pytest.approx(5)
    assert result.source == result.load
    result = stability_circles(((0, 0), (0, 0.5)))
    assert result.source is None
    assert result.load is not None
    assert result.load.center_r == 2
    assert result.load.radius == 0
    assert "degenerate" in " ".join(result.warnings)


@pytest.mark.parametrize("reflection,defined", [(1e-8, False), (1e-7, True)])
def test_negligible_denominator_threshold(reflection: float, defined: bool) -> None:
    result = stability_circles(((0, 0), (0, reflection)))
    assert (result.load is not None) == defined
    assert result.source is None


@pytest.mark.parametrize(
    "matrix",
    [
        [],
        [[0]],
        [[True, 0], [0, 0]],
        [[float("nan"), 0], [0, 0]],
        [[complex(0, float("inf")), 0], [0, 0]],
        [[1e308, 0], [0, 1e308]],
    ],
)
def test_invalid_input_or_numeric_overflow_rejected(matrix: list) -> None:
    with pytest.raises(ValueError):
        stability_circles(matrix)


def test_source_fingerprint() -> None:
    path = (
        Path(__file__).resolve().parents[2]
        / "PA design App"
        / "src"
        / "modules"
        / "rf_tools"
        / "sp_parsers.R"
    )
    assert (
        hashlib.md5(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        == (REFERENCE["provenance"]["source_md5"])
    )
