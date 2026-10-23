import hashlib
import json
from pathlib import Path
from typing import Any

import pytest
from pydantic import ValidationError

from rfview.domain.guardrails import (
    DeviceParameters,
    GuardrailCatalog,
    validate_device_params,
)
from rfview.services import read_guardrails

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "PA design App" / "config" / "technology_guardrails.yaml"
REFERENCE = json.loads(
    (Path(__file__).parent / "fixtures" / "guardrail_reference.json").read_text(encoding="utf-8")
)


@pytest.fixture
def catalog() -> GuardrailCatalog:
    return read_guardrails(CONFIG)


@pytest.mark.parametrize("case", REFERENCE["cases"], ids=lambda case: case["name"])
def test_validation_matches_recorded_r(case: dict[str, Any], catalog: GuardrailCatalog) -> None:
    result = validate_device_params(DeviceParameters.model_validate(case["inputs"]), catalog)
    expected = case["expected"]
    assert result.status == expected["status"]
    assert len(result.errors) == expected["error_count"]
    assert len(result.warnings) == expected["warning_count"]
    assert result.tech == expected["tech"]
    assert result.freq_ghz == expected["freq_ghz"]
    assert result.max_gain_available == expected["max_gain_available"]
    assert result.pae_max_practical == expected["pae_max_practical"]


def test_guardrail_reference_source_revision() -> None:
    for path, key in (
        (CONFIG, "config_md5"),
        (
            ROOT / "PA design App" / "src" / "modules" / "calculations" / "calc_guardrails.R",
            "source_md5",
        ),
    ):
        normalized = path.read_bytes().replace(b"\r\n", b"\n")
        assert hashlib.md5(normalized).hexdigest() == REFERENCE["provenance"][key]


def test_unknown_technology_is_explicit(catalog: GuardrailCatalog) -> None:
    device = DeviceParameters(
        tech_key="unknown", freq_ghz=3.5, gain_db=15, pae_pct=50, pout_dbm=40, vdd=28
    )
    with pytest.raises(ValueError, match="Unknown technology"):
        validate_device_params(device, catalog)


@pytest.mark.parametrize(
    "field,value",
    [
        ("freq_ghz", 0),
        ("freq_ghz", float("nan")),
        ("gain_db", float("inf")),
        ("pae_pct", -1),
        ("pae_pct", 101),
        ("pout_dbm", float("-inf")),
        ("vdd", 0),
        ("pout_density", -1),
        ("gain_db", True),
    ],
)
def test_invalid_device_inputs_are_not_success_shaped(field: str, value: object) -> None:
    data: dict[str, object] = dict(
        tech_key="GaN_SiC", freq_ghz=3.5, gain_db=15, pae_pct=50, pout_dbm=40, vdd=28
    )
    data[field] = value
    with pytest.raises(ValidationError):
        DeviceParameters.model_validate(data)


@pytest.mark.parametrize(
    "text",
    [
        "technologies: [",
        "!!python/object/apply:builtins.print ['unsafe']",
        "technologies: {}",
        "technologies: {GaN_SiC: {label: incomplete}}",
    ],
)
def test_invalid_yaml_never_uses_embedded_fallback(tmp_path: Path, text: str) -> None:
    path = tmp_path / "limits.yaml"
    path.write_text(text, encoding="utf-8")
    with pytest.raises(ValueError):
        read_guardrails(path)


def test_missing_yaml_is_not_silently_replaced(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError):
        read_guardrails(tmp_path / "missing.yaml")


def test_catalog_constraints_and_validation_do_not_mutate(catalog: GuardrailCatalog) -> None:
    before = catalog.model_dump()
    device = DeviceParameters(
        tech_key="GaN_SiC", freq_ghz=3.5, gain_db=15, pae_pct=50, pout_dbm=40, vdd=28
    )
    assert validate_device_params(device, catalog).status == "ok"
    assert catalog.model_dump() == before
    invalid = catalog.model_dump()
    invalid["technologies"]["GaN_SiC"]["freq_range_ghz"]["sweet_spot_min"] = 100
    with pytest.raises(ValidationError, match="sweet spot"):
        GuardrailCatalog.model_validate(invalid)
    invalid = catalog.model_dump()
    invalid["validation_rules"]["gain_vs_freq"]["error_margin_db"] = 1
    with pytest.raises(ValidationError, match="warning margin"):
        GuardrailCatalog.model_validate(invalid)
