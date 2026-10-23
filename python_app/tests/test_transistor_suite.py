import hashlib
import json
from pathlib import Path
from typing import Any

import pytest
from pydantic import ValidationError

from rfview.domain.transistor import StageSizingInput, transistor_design_suite

REFERENCE = json.loads(
    (Path(__file__).parent / "fixtures" / "transistor_suite_reference.json").read_text(
        encoding="utf-8"
    )
)


def equivalent(actual: Any, expected: Any) -> None:
    if isinstance(expected, dict):
        for key, value in expected.items():
            equivalent(actual[key], value)
    elif isinstance(expected, (str, bool)) or expected is None:
        assert actual == expected
    else:
        assert actual == pytest.approx(expected, rel=1e-10, abs=1e-12)


@pytest.mark.parametrize("case", REFERENCE["cases"], ids=lambda case: case["name"])
def test_full_suite_matches_r(case: dict[str, Any]) -> None:
    stage = StageSizingInput.model_validate(case["stage"] or {})
    before = stage.model_dump()
    result = transistor_design_suite(
        stage, case["freq_ghz"], case["topology"], case["er"], case["h_mm"]
    )
    equivalent(result, case["expected"])
    assert result["model_version"] == "legacy-r-transistor-suite-v1"
    assert result["limitations"]
    json.dumps(result, allow_nan=False)
    assert stage.model_dump() == before


@pytest.mark.parametrize(
    "data",
    [
        {"pout_dbm": float("nan")},
        {"pout_dbm": True},
        {"pae_pct": 0},
        {"pae_pct": 101},
        {"vdd_v": 2},
        {"unknown": 1},
    ],
)
def test_invalid_stage_rejected(data: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        StageSizingInput.model_validate(data)


@pytest.mark.parametrize(
    "kwargs",
    [
        {"freq_ghz": 0},
        {"freq_ghz": float("inf")},
        {"freq_ghz": 3.5, "er": 0.9},
        {"freq_ghz": 3.5, "h_mm": 0},
        {"freq_ghz": 3.5, "topology": "not-a-topology"},
    ],
)
def test_invalid_suite_inputs_raise(kwargs: dict[str, Any]) -> None:
    with pytest.raises(ValueError):
        transistor_design_suite(StageSizingInput(), **kwargs)


def test_legacy_efficiency_does_not_change_gate_width() -> None:
    low = transistor_design_suite(StageSizingInput(pout_dbm=40, pae_pct=10), 3.5)
    high = transistor_design_suite(StageSizingInput(pout_dbm=40, pae_pct=80), 3.5)
    assert low["gate_width"]["gate_width_mm"] == high["gate_width"]["gate_width_mm"] == 4
    assert low["ropt"]["Ropt_ohm"] == high["ropt"]["Ropt_ohm"] == 33.8


def test_suite_reference_matches_source() -> None:
    source = (
        Path(__file__).resolve().parents[2]
        / "PA design App"
        / "src"
        / "modules"
        / "calculations"
        / "calc_transistor_sizing.R"
    )
    content = source.read_bytes().replace(b"\r\n", b"\n")
    assert hashlib.md5(content).hexdigest() == REFERENCE["provenance"]["source_md5"]
