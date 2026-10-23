import hashlib
import json
from pathlib import Path
from typing import Any

import pytest

from rfview.domain.network_parameters import s_to_y, s_to_z
from rfview.services import read_touchstone

FIXTURES = Path(__file__).parent / "fixtures"
REFERENCE = json.loads((FIXTURES / "network_parameters_reference.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("case", REFERENCE["cases"], ids=lambda case: case["name"])
@pytest.mark.parametrize("target,convert", [("z", s_to_z), ("y", s_to_y)])
def test_matches_r(case: dict[str, Any], target: str, convert: Any) -> None:
    source = [[complex(p["real"], p["imag"]) for p in row] for row in case["s"]]
    before = [row[:] for row in source]
    result = convert(source, case["z0"])
    for row in range(2):
        for col in range(2):
            point = case[target][row][col]
            assert result[row][col] == pytest.approx(
                complex(point["real"], point["imag"]), rel=1e-10, abs=1e-12
            )
    assert source == before
    assert isinstance(result, tuple) and isinstance(result[0], tuple)


@pytest.mark.parametrize("convert,diagonal", [(s_to_z, 1), (s_to_y, -1)])
@pytest.mark.parametrize("delta", [0, 1e-16])
def test_singular_and_near_singular_are_explicit(convert: Any, diagonal: int, delta: float) -> None:
    with pytest.raises(ValueError, match="singular"):
        convert([[diagonal * (1 - delta), 0], [0, 0]])


@pytest.mark.parametrize("convert", [s_to_z, s_to_y])
@pytest.mark.parametrize(
    "matrix",
    [
        [],
        [[0]],
        [[0, 0]],
        [[0, 0, 0], [0, 0]],
        [[float("nan"), 0], [0, 0]],
        [[complex(0, float("inf")), 0], [0, 0]],
        [[True, 0], [0, 0]],
        [["0.1", 0], [0, 0]],
    ],
)
def test_invalid_matrix_fails(convert: Any, matrix: Any) -> None:
    with pytest.raises(ValueError):
        convert(matrix)


@pytest.mark.parametrize("convert", [s_to_z, s_to_y])
@pytest.mark.parametrize("z0", [0, -50, float("nan"), float("inf"), True])
def test_invalid_reference_impedance(convert: Any, z0: float) -> None:
    with pytest.raises(ValueError):
        convert([[0, 0], [0, 0]], z0)


def test_touchstone_matrix_orientation_and_inverse_identity() -> None:
    network = read_touchstone(FIXTURES / "touchstone" / "reference_ri.s2p")
    p = {point.param: complex(point.real, point.imag) for point in network.points[:4]}
    s = ((p["S11"], p["S12"]), (p["S21"], p["S22"]))
    z, y = s_to_z(s, network.z0), s_to_y(s, network.z0)
    for row in range(2):
        for col in range(2):
            product = sum(z[row][k] * y[k][col] for k in range(2))
            assert product == pytest.approx(1 if row == col else 0, abs=1e-12)
    assert z[1][0] / z[0][1] == pytest.approx(p["S21"] / p["S12"])


@pytest.mark.parametrize("convert", [s_to_z, s_to_y])
def test_numeric_overflow_is_explicit(convert: Any) -> None:
    with pytest.raises(ValueError, match="numeric range"):
        convert([[1e308, 1e308], [1e308, 1e308]])


def test_reference_source_revision() -> None:
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
