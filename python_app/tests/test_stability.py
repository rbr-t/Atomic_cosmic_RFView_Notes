import hashlib
import json
from pathlib import Path

import pytest

from rfview.domain.stability import stability_metrics

REFERENCE = json.loads(
    (Path(__file__).parent / "fixtures" / "stability_reference.json").read_text(encoding="utf-8")
)


@pytest.mark.parametrize("case", REFERENCE["cases"], ids=lambda case: case["name"])
def test_legacy_reference(case: dict) -> None:
    matrix = [[complex(v["real"], v["imag"]) for v in row] for row in case["s"]]
    before = [row[:] for row in matrix]
    result = stability_metrics(matrix)
    actual = result.model_dump()
    for key, expected in case["expected"].items():
        if expected is None or isinstance(expected, bool):
            assert actual[key] == expected, key
        else:
            assert actual[key] == pytest.approx(expected, rel=1e-10, abs=1e-12), key
    assert matrix == before
    assert result.warnings
    json.dumps(actual, allow_nan=False)


def test_known_bilateral_metrics_and_legacy_gain_scale() -> None:
    result = stability_metrics(((0, 0.1), (2, 0)))
    assert result.delta_mag == pytest.approx(0.2)
    assert result.K == pytest.approx(2.6)
    assert result.mu_in == pytest.approx(5)
    assert result.mu_out == pytest.approx(5)
    assert result.B1 == pytest.approx(0.96)
    assert result.msg_db == pytest.approx(26.0205999133)
    assert result.stable


def test_matched_metrics_are_explicitly_undefined() -> None:
    result = stability_metrics(((0, 0), (0, 0)))
    assert result.K is None
    assert result.mu_in is None
    assert result.mu_out is None
    assert result.msg_db is None
    assert not result.stable
    assert any("undefined" in message for message in result.warnings)


@pytest.mark.parametrize(
    "matrix",
    [
        [],
        [[0]],
        [[True, 0], [0, 0]],
        [[float("nan"), 0], [0, 0]],
        [[complex(0, float("inf")), 0], [0, 0]],
        [[1e308, 1e308], [1e308, 1e308]],
    ],
)
def test_invalid_numeric_input_raises(matrix: list) -> None:
    with pytest.raises(ValueError):
        stability_metrics(matrix)


def test_large_k_has_finite_cancellation_safe_gain() -> None:
    result = stability_metrics(((0.1, 1e-10), (1, 0.2)))
    assert result.mag_db is not None
    assert result.K is not None and result.K > 1e8
    result.model_dump_json()


def test_oracle_source_revision() -> None:
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
