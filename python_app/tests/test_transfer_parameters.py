import hashlib
import json
from pathlib import Path
from typing import Any

import pytest

from rfview.domain.network_parameters import s_to_abcd, s_to_h, s_to_t

REFERENCE = json.loads(
    (Path(__file__).parent / "fixtures" / "transfer_parameters_reference.json").read_text(
        encoding="utf-8"
    )
)


@pytest.mark.parametrize("case", REFERENCE["cases"], ids=lambda case: case["name"])
@pytest.mark.parametrize("target,convert", [("h", s_to_h), ("abcd", s_to_abcd), ("t", s_to_t)])
def test_r_reference(case: dict, target: str, convert: Any) -> None:
    s = [[complex(p["real"], p["imag"]) for p in row] for row in case["s"]]
    before = [row[:] for row in s]
    args = (s,) if target == "t" else (s, case["z0"])
    expected = case[target]
    if expected is None:
        with pytest.raises(ValueError, match="singular"):
            convert(*args)
    else:
        result = convert(*args)
        for row in range(2):
            for col in range(2):
                p = expected[row][col]
                assert result[row][col] == pytest.approx(
                    complex(p["real"], p["imag"]), rel=1e-10, abs=1e-12
                )
    assert s == before


def test_through_network_and_transfer_wave_identity() -> None:
    through = ((0, 1), (1, 0))
    assert s_to_abcd(through) == ((1, 0), (0, 1))
    assert s_to_t(through) == ((1, 0), (0, 1))
    s = ((0.1 + 0.2j, 0.03 + 0.04j), (2 - 0.5j, -0.2 + 0.1j))
    a1, a2 = 0.4 - 0.2j, -0.3 + 0.1j
    b1, b2 = s[0][0] * a1 + s[0][1] * a2, s[1][0] * a1 + s[1][1] * a2
    t = s_to_t(s)
    assert t[0][0] * a2 + t[0][1] * b2 == pytest.approx(b1)
    assert t[1][0] * a2 + t[1][1] * b2 == pytest.approx(a1)
    z0 = 75
    abcd = s_to_abcd(s, z0)
    v1, v2 = (a1 + b1) * z0**0.5, (a2 + b2) * z0**0.5
    i1, i2 = (a1 - b1) / z0**0.5, (a2 - b2) / z0**0.5
    assert abcd[0][0] * v2 - abcd[0][1] * i2 == pytest.approx(v1)
    assert abcd[1][0] * v2 - abcd[1][1] * i2 == pytest.approx(i1)
    h = s_to_h(s, z0)
    assert h[0][0] * i1 + h[0][1] * v2 == pytest.approx(v1)
    assert h[1][0] * i1 + h[1][1] * v2 == pytest.approx(i2)


@pytest.mark.parametrize("convert", [s_to_h, s_to_abcd, s_to_t])
@pytest.mark.parametrize(
    "s", [[], [[True, 0], [1, 0]], [[float("nan"), 0], [1, 0]], [[1e308] * 2] * 2]
)
def test_invalid_and_overflow_rejected(convert: Any, s: list) -> None:
    with pytest.raises(ValueError):
        convert(s)


@pytest.mark.parametrize("convert", [s_to_h, s_to_abcd])
@pytest.mark.parametrize("z0", [True, 0, -1, float("inf")])
def test_invalid_reference(convert: Any, z0: float) -> None:
    with pytest.raises(ValueError):
        convert(((0, 1), (1, 0)), z0)


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
        == REFERENCE["provenance"]["source_md5"]
    )


@pytest.mark.parametrize("convert,threshold", [(s_to_abcd, 0.5e-15), (s_to_t, 1e-15)])
def test_transfer_threshold_preserves_legacy_strict_comparison(
    convert: Any, threshold: float
) -> None:
    with pytest.raises(ValueError, match="singular"):
        convert(((0, 0.1), (threshold / 2, 0)))
    result = convert(((0, 0.1), (threshold, 0)))
    assert result[1][1].real > 0
