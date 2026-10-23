import hashlib
import json
from pathlib import Path
from typing import Any

import pytest

from rfview.domain import guardrails, planning, rf_tools, transistor
from rfview.domain.lineup import calculate_lineup
from rfview.domain.models import LineupDocument

REFERENCE = json.loads(
    (Path(__file__).parent / "fixtures" / "legacy_reference.json").read_text(encoding="utf-8")
)


def assert_equivalent(actual: Any, expected: Any) -> None:
    if isinstance(expected, dict):
        for key, value in expected.items():
            assert key in actual, f"Missing result field: {key}"
            assert_equivalent(actual[key], value)
    elif isinstance(expected, list):
        assert len(actual) == len(expected)
        for left, right in zip(actual, expected, strict=True):
            assert_equivalent(left, right)
    elif isinstance(expected, bool) or expected is None or isinstance(expected, str):
        assert actual == expected
    else:
        assert actual == pytest.approx(expected, rel=1e-10, abs=1e-12)


@pytest.mark.parametrize("case", REFERENCE["lineups"], ids=lambda case: case["name"])
def test_lineup_matches_recorded_r(case: dict[str, Any]) -> None:
    document = LineupDocument.model_validate(case["document"])
    result = calculate_lineup(
        document, case["input_power_dbm"], case["backoff_db"], case["architecture"]
    ).model_dump(exclude_none=True)
    expected = case["expected"]
    # Human-readable text and diagnostics are intentionally more explicit in Python.
    for key in ("rationale", "warnings", "phase_results"):
        expected = {name: value for name, value in expected.items() if name != key}
    assert_equivalent(result, expected)
    for actual_phase, expected_phase in zip(
        result["phase_results"], case["expected"]["phase_results"], strict=True
    ):
        assert_equivalent(
            actual_phase, {key: value for key, value in expected_phase.items() if key != "notes"}
        )


FUNCTIONS = {
    **{
        name: getattr(planning, name)
        for name in (
            "atmospheric_loss",
            "efficiency",
            "recommend_technology",
            "passive_loss",
            "link_budget",
        )
    },
    **{name: getattr(guardrails, name) for name in ("available_gain", "pae_backoff")},
    **{
        name: getattr(transistor, name)
        for name in (
            "ropt",
            "gate_width",
            "idq",
            "doherty_sizing",
            "matching_lmatch",
            "doherty_combiner",
        )
    },
    **{
        name: getattr(rf_tools, name)
        for name in (
            "power_from_watts",
            "power_from_dbm",
            "power_from_voltage",
            "wavelengths",
            "sparams",
            "thermal",
        )
    },
}


@pytest.mark.parametrize("case", REFERENCE["scalars"])
def test_scalar_matches_recorded_r(case: dict[str, Any]) -> None:
    assert_equivalent(FUNCTIONS[case["name"]](*case["arguments"]), case["expected"])


def test_reference_matches_legacy_source_revision() -> None:
    calc = (
        Path(__file__).resolve().parents[2] / "PA design App" / "src" / "modules" / "calculations"
    )
    for name, expected in REFERENCE["provenance"]["source_md5"].items():
        content = (calc / name).read_bytes().replace(b"\r\n", b"\n")
        assert hashlib.md5(content).hexdigest() == expected
