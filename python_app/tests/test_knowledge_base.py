import hashlib
import json
import math
from pathlib import Path

import pytest
from pydantic import ValidationError

import rfview.knowledge_base as knowledge_base
from rfview.knowledge_base import (
    MAX_KB_FILE_BYTES,
    DeviceRecord,
    DeviceSearch,
    load_device_catalog,
    search_devices,
)

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEVICE_KB_ROOT = REPOSITORY_ROOT / "PA design App" / "data" / "kb"


def write_vendor(root: Path, name: str, data: str) -> Path:
    vendor = root / name
    vendor.mkdir(parents=True, exist_ok=True)
    source = vendor / "devices.json"
    source.write_text(data, encoding="utf-8")
    return source


def record(
    identifier: str = "vendor_part",
    *,
    part: str = "PART",
    manufacturer: str = "Vendor",
    technology: str = "LDMOS",
    low: float = 100,
    high: float = 1000,
    extra: dict[str, object] | None = None,
) -> dict[str, object]:
    result: dict[str, object] = {
        "device_id": identifier,
        "part_number": part,
        "manufacturer": manufacturer,
        "technology": technology,
        "freq_min_mhz": low,
        "freq_max_mhz": high,
        "vdd_v": 28,
        "pout_w_cw": 10,
        "drain_eff_pct": 55,
        "knowledge_source": "datasheet",
        "knowledge_confidence": "high",
        "datasheet_url": "https://vendor.example/datasheet.pdf",
        "tags": ["Doherty", "mobile"],
        "app_notes": [{"title": "Application note"}],
    }
    if extra:
        result.update(extra)
    return result


def test_reads_all_checked_in_records_with_digest_and_extra_fields() -> None:
    catalog = load_device_catalog(DEVICE_KB_ROOT)
    assert len(catalog) == 22
    assert {item.source_file.split("/", 1)[0] for item in catalog} == {
        "ampleon",
        "guerrilla_rf",
        "nxp",
        "qorvo",
    }
    assert len({item.record.device_id for item in catalog}) == 22
    ampleon = next(item for item in catalog if item.record.device_id == "ampleon_BLF188XR")
    assert ampleon.record.technology == "LDMOS"
    assert ampleon.record.knowledge_source == "from_training"
    assert ampleon.record.app_notes
    assert ampleon.record.application
    source_bytes = (DEVICE_KB_ROOT / ampleon.source_file).read_bytes()
    assert ampleon.source_sha256 == hashlib.sha256(source_bytes).hexdigest()


def test_search_text_and_exact_manufacturer_technology_filters_and_frequency_edges(
    tmp_path: Path,
) -> None:
    first = record(
        "vendor_alpha",
        part="PA-α",
        manufacturer="Example Labs",
        technology="GaN-SiC",
        low=100,
        high=500,
        extra={"custom_data": {"application": "5G-Sub6"}},
    )
    second = record("other_beta", part="Beta", low=500, high=2000)
    write_vendor(tmp_path, "vendor", json.dumps([first, second]))
    catalog = load_device_catalog(tmp_path)

    exact = search_devices(
        catalog,
        DeviceSearch(
            query="5g-sub6",
            manufacturer="example labs",
            technology="gan-sic",
            frequency_mhz=500,
        ),
    )
    assert exact.total_matches == 1
    assert exact.items[0].record.device_id == "vendor_alpha"

    boundary = search_devices(catalog, DeviceSearch(frequency_mhz=500))
    assert [item.record.device_id for item in boundary.items] == ["vendor_alpha", "other_beta"]
    assert search_devices(catalog, DeviceSearch(query="nomatch")).items == ()


def test_search_is_casefolded_deterministic_and_reports_truncation(tmp_path: Path) -> None:
    records = [
        record("v_z", part="Zulu", manufacturer="ZZ", extra={"notes": "Doherty"}),
        record("v_b", part="beta", manufacturer="aa", extra={"notes": "Doherty"}),
        record("v_a", part="Alpha", manufacturer="AA", extra={"notes": "Doherty"}),
    ]
    write_vendor(tmp_path, "vendor", json.dumps(records))
    catalog = load_device_catalog(tmp_path)
    results = search_devices(catalog, DeviceSearch(query="DOHERTY", max_results=2))
    assert results.total_matches == 3
    assert results.truncated
    assert [item.record.device_id for item in results.items] == ["v_a", "v_b"]


def test_empty_or_missing_catalog_is_explicit(tmp_path: Path) -> None:
    empty = tmp_path / "empty"
    empty.mkdir()
    with pytest.raises(ValueError, match="No vendor"):
        load_device_catalog(empty)
    with pytest.raises(ValueError, match="existing"):
        load_device_catalog(tmp_path / "missing")


@pytest.mark.parametrize(
    ("content", "message"),
    [
        ('{"not":"an array"}', "JSON array"),
        ("[null]", "must be an object"),
        ("[{", "Invalid UTF-8 JSON"),
        ('[{"device_id":"first","device_id":"last"}]', "Duplicate JSON object key"),
        ("[NaN]", "Non-finite JSON constant"),
        ('[{"number":1e999}]', "Non-finite JSON number"),
        ("[]", "No vendor"),
    ],
)
def test_invalid_sources_are_rejected_without_partial_catalog(
    tmp_path: Path, content: str, message: str
) -> None:
    write_vendor(tmp_path, "vendor", content)
    with pytest.raises(ValueError, match=message):
        load_device_catalog(tmp_path)


@pytest.mark.parametrize(
    "payload",
    [
        {"part_number": None},
        {"technology": ""},
        {"freq_min_mhz": -1},
        {"freq_min_mhz": 1000, "freq_max_mhz": 999},
        {"freq_min_mhz": True},
        {"freq_max_mhz": "1000"},
        {"drain_eff_pct": 101},
        {"pout_w_cw": -1},
        {"gain_db": float("inf")},
    ],
)
def test_invalid_or_nonphysical_record_fields_fail_closed(
    tmp_path: Path, payload: dict[str, object]
) -> None:
    write_vendor(tmp_path, "vendor", json.dumps([record(extra=payload)]))
    with pytest.raises(ValueError, match="Invalid KB (record|JSON)"):
        load_device_catalog(tmp_path)


def test_invalid_optional_numeric_in_record_model_is_rejected() -> None:
    with pytest.raises(ValidationError):
        DeviceRecord.model_validate(record(extra={"vdd_v": "twenty-eight"}))
    with pytest.raises(ValidationError):
        DeviceRecord.model_validate(record(extra={"vdd_v": math.nan}))


def test_missing_required_record_keys_fail_with_location(tmp_path: Path) -> None:
    invalid = record()
    invalid.pop("device_id")
    write_vendor(tmp_path, "vendor", json.dumps([invalid]))
    with pytest.raises(ValueError, match="Invalid KB record 0"):
        load_device_catalog(tmp_path)


def test_duplicate_device_ids_across_vendor_files_rejected(tmp_path: Path) -> None:
    write_vendor(tmp_path, "one", json.dumps([record("shared")]))
    write_vendor(tmp_path, "two", json.dumps([record("shared")]))
    with pytest.raises(ValueError, match="Duplicate KB device_id"):
        load_device_catalog(tmp_path)


def test_bad_source_does_not_return_other_vendors_partially(tmp_path: Path) -> None:
    write_vendor(tmp_path, "one", json.dumps([record("valid")]))
    write_vendor(tmp_path, "two", "[")
    with pytest.raises(ValueError, match="Invalid UTF-8 JSON"):
        load_device_catalog(tmp_path)


def test_per_file_size_gate(tmp_path: Path) -> None:
    source = write_vendor(tmp_path, "vendor", " " * (MAX_KB_FILE_BYTES + 1))
    with pytest.raises(ValueError, match="8 MiB"):
        load_device_catalog(tmp_path)
    assert source.stat().st_size == MAX_KB_FILE_BYTES + 1


def test_combined_source_size_gate(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    write_vendor(tmp_path, "one", json.dumps([record("first")]))
    write_vendor(tmp_path, "two", json.dumps([record("second")]))
    monkeypatch.setattr(knowledge_base, "MAX_KB_TOTAL_BYTES", 1)
    with pytest.raises(ValueError, match="Combined KB sources"):
        load_device_catalog(tmp_path)


def test_device_count_gate(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    write_vendor(tmp_path, "vendor", json.dumps([record("first"), record("second")]))
    monkeypatch.setattr(knowledge_base, "MAX_KB_DEVICES", 1)
    with pytest.raises(ValueError, match="10,000-record"):
        load_device_catalog(tmp_path)


def test_vendor_hidden_directories_and_non_vendor_files_ignored(tmp_path: Path) -> None:
    write_vendor(tmp_path, "vendor", json.dumps([record()]))
    (tmp_path / "_extracted").mkdir()
    (tmp_path / "_extracted" / "devices.json").write_text(
        json.dumps([record("hidden")]), encoding="utf-8"
    )
    (tmp_path / "notes.json").write_text(json.dumps([record("not-a-vendor")]), encoding="utf-8")
    catalog = load_device_catalog(tmp_path)
    assert [item.record.device_id for item in catalog] == ["vendor_part"]


@pytest.mark.parametrize(
    "payload",
    [
        {"max_results": 0},
        {"max_results": 201},
        {"max_results": True},
        {"frequency_mhz": 0},
        {"frequency_mhz": math.inf},
        {"frequency_mhz": True},
        {"query": "q" * 161},
        {"manufacturer": "x" * 121},
    ],
)
def test_search_filter_bounds_and_nonfinite_inputs_rejected(
    payload: dict[str, object],
) -> None:
    with pytest.raises(ValidationError):
        DeviceSearch.model_validate(payload)


def test_query_whitespace_becomes_no_text_filter(tmp_path: Path) -> None:
    write_vendor(tmp_path, "vendor", json.dumps([record()]))
    results = search_devices(load_device_catalog(tmp_path), DeviceSearch(query="   "))
    assert results.total_matches == 1


def test_catalog_source_symlinks_are_not_followed(tmp_path: Path) -> None:
    root = tmp_path / "root"
    root.mkdir()
    target = tmp_path / "target"
    target.mkdir()
    write_vendor(target, "vendor", json.dumps([record()]))
    try:
        (root / "linked").symlink_to(target, target_is_directory=True)
    except OSError:
        pytest.skip("Creating directory symlinks is not permitted on this Windows account")
    with pytest.raises(ValueError, match="symlink"):
        load_device_catalog(root)
