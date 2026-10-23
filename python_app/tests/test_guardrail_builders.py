import hashlib
import json
from pathlib import Path
from typing import Any

import pytest

from rfview.domain.guardrails import (
    GuardrailCatalog,
    build_design_space_data,
    build_gain_bandwidth_data,
    build_guardrail_summary_table,
    build_pae_backoff_data,
)
from rfview.services import read_guardrails

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "PA design App" / "config" / "technology_guardrails.yaml"
REFERENCE = json.loads(
    (Path(__file__).parent / "fixtures" / "guardrail_builders_reference.json").read_text(
        encoding="utf-8"
    )
)


@pytest.fixture
def catalog() -> GuardrailCatalog:
    return read_guardrails(CONFIG)


def assert_rows(actual: Any, expected: Any) -> None:
    assert len(actual) == len(expected)
    for left, right in zip(actual, expected, strict=True):
        assert left.keys() == right.keys()
        for key, value in right.items():
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                assert left[key] == pytest.approx(value, rel=1e-10, abs=1e-12), key
            else:
                assert left[key] == value, key


@pytest.mark.parametrize(
    "name",
    [
        "design_space",
        "design_space_single",
        "design_space_three",
        "gain_bandwidth",
        "pae_backoff",
        "summary",
    ],
)
def test_complete_builder_rows_match_r(name: str, catalog: GuardrailCatalog) -> None:
    match name:
        case "design_space":
            actual = build_design_space_data(catalog)
        case "design_space_single":
            actual = build_design_space_data(catalog, 1)
        case "design_space_three":
            actual = build_design_space_data(catalog, 3)
        case "gain_bandwidth":
            actual = build_gain_bandwidth_data(catalog)
        case "pae_backoff":
            actual = build_pae_backoff_data(catalog)
        case _:
            actual = build_guardrail_summary_table(catalog)
    expected = REFERENCE["builders"][name]
    if name == "summary":
        expected = [
            {**row, "Pout density W/mm": density}
            for row, density in zip(
                expected, REFERENCE["summary_density_two_decimals"], strict=True
            )
        ]
    assert_rows(actual, expected)


@pytest.mark.parametrize("count", [0, -1, True, 2.5, "3"])
def test_bad_sample_counts_raise(catalog: GuardrailCatalog, count: Any) -> None:
    with pytest.raises(ValueError, match="positive integer"):
        build_design_space_data(catalog, count)


def test_output_shapes_order_and_isolation(catalog: GuardrailCatalog) -> None:
    original = catalog.model_dump()
    design = build_design_space_data(catalog)
    assert len(design) == 6 * 60
    assert len(build_pae_backoff_data(catalog)) == 6 * 5 * 65
    assert len(build_guardrail_summary_table(catalog)) == 6
    assert list(dict.fromkeys(row["tech"] for row in design)) == list(catalog.technologies)
    for key in catalog.technologies:
        freqs = [row["freq_ghz"] for row in design if row["tech"] == key]
        assert freqs == sorted(freqs)
    design[0]["gain_db"] = -999
    assert build_design_space_data(catalog)[0]["gain_db"] >= 0
    assert catalog.model_dump() == original


def test_optional_fields_keep_builder_specific_legacy_defaults() -> None:
    catalog = GuardrailCatalog.model_validate(
        {
            "technologies": {
                "minimal": {
                    "label": "Minimal",
                    "freq_range_ghz": {
                        "min": 1,
                        "max": 10,
                        "sweet_spot_min": 2,
                        "sweet_spot_max": 8,
                    },
                    "gain_db": {"ft_ghz_typical": 50},
                    "pae_pct": {},
                    "vdd": {"typical": 28},
                    "pout_density_w_per_mm": {},
                }
            }
        }
    )
    design = build_design_space_data(catalog, 1)[0]
    assert design["pout_density_typ"] == 1
    assert design["pout_density_max"] == 2
    assert design["pae_typ_pct"] == 45
    assert design["pae_max_pct"] == 65
    assert build_pae_backoff_data(catalog)[0]["pae_pct"] == 45
    summary = build_guardrail_summary_table(catalog)[0]
    assert summary["PAE P3dB max (%)"] is None
    assert summary["Max Tj (\u00b0C)"] is None
    assert summary["Pout density W/mm"] == "0.00 \u2013 0.00"
    gains = build_gain_bandwidth_data(catalog)
    assert gains
    assert all(row["gain_max"] >= row["gain_typ"] for row in gains)


def test_builder_oracle_matches_sources() -> None:
    for path, key in (
        (CONFIG, "config_md5"),
        (
            ROOT / "PA design App" / "src" / "modules" / "calculations" / "calc_guardrails.R",
            "source_md5",
        ),
    ):
        normalized = path.read_bytes().replace(b"\r\n", b"\n")
        assert hashlib.md5(normalized).hexdigest() == REFERENCE["provenance"][key]
