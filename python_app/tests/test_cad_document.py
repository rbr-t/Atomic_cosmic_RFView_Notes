import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from rfview.domain.cad import (
    MAX_CAD_BYTES,
    CADComponent,
    CADDesign,
    parse_cad_design,
    serialize_cad_design,
)
from rfview.services import read_cad_design


def component(identifier: str, kind: str, params: dict[str, object]) -> dict[str, object]:
    return {
        "id": identifier,
        "type": kind,
        "name": f"Imported {kind}",
        "x": 12,
        "y": -5.25,
        "rotation": 45,
        "layer": "metal_top",
        "params": params,
        "vendor_extension": {"retained": [None, True, 1]},
    }


def legacy_document() -> dict[str, object]:
    return {
        "version": "1.0",
        "substrate": {
            "er": 3.55,
            "tanD": 0.0027,
            "h": 0.508,
            "t": 0.035,
            "vendor": "Rogers",
        },
        "components": [
            component("cmp_1", "microstrip", {"W": 0.5, "L": 5, "vendor_param": "x"}),
            component("cmp_2", "bend90", {"W": 0.6, "L": 4, "miter": True}),
            component("cmp_3", "tee", {"W": 0.5, "L": 3}),
            component("cmp_4", "coupled", {"W": 0.3, "L": 8, "gap": 0.2}),
            component("cmp_5", "via", {"drill": 0.2, "pad": 0.5}),
            component("cmp_6", "port", {"W": 0.5, "portNum": 1}),
            component("cmp_7", "open_stub", {"W": 0.5, "L": 2.5}),
            component("cmp_8", "short_stub", {"W": 0.5, "L": 2.5}),
        ],
        "vendor_document_field": {"future": "preserve"},
    }


def test_actual_legacy_v1_shapes_round_trip_all_known_types_and_unknown_fields() -> None:
    source = legacy_document()
    parsed = parse_cad_design(json.dumps(source))
    encoded = json.loads(serialize_cad_design(parsed))
    assert [item["type"] for item in encoded["components"]] == [
        "microstrip",
        "bend90",
        "tee",
        "coupled",
        "via",
        "port",
        "open_stub",
        "short_stub",
    ]
    assert encoded["vendor_document_field"] == source["vendor_document_field"]
    assert encoded["substrate"]["vendor"] == "Rogers"
    assert encoded["components"][0]["vendor_extension"] == {"retained": [None, True, 1]}
    assert encoded["components"][0]["params"]["vendor_param"] == "x"
    assert encoded["components"][0]["x"] == 12


def test_palette_microstrip_alias_is_preserved_not_silently_rewritten() -> None:
    parsed = parse_cad_design(json.dumps([component("cmp_1", "ms", {"W": 0.5, "L": 5})]))
    assert parsed.components[0].type == "ms"
    exported = json.loads(serialize_cad_design(parsed))
    assert exported["components"][0]["type"] == "ms"


@pytest.mark.parametrize(
    "params",
    [
        {},
        {"W": 0},
        {"L": -1},
        {"W": "0.5", "L": 2},
        {"W": True, "L": 2},
        {"W": float("inf"), "L": 2},
    ],
)
def test_invalid_known_microstrip_geometry_is_rejected(params: dict[str, object]) -> None:
    with pytest.raises((ValueError, ValidationError)):
        CADComponent.model_validate(component("cmp_1", "microstrip", params))


@pytest.mark.parametrize(
    ("kind", "params"),
    [
        ("coupled", {"W": 0.5, "L": 2, "gap": 0}),
        ("via", {"drill": -0.1, "pad": 0.5}),
        ("port", {"W": 0.5, "portNum": 0}),
        ("port", {"W": 0.5, "portNum": 1.5}),
        ("bend90", {"W": 0.5, "L": 2, "miter": "yes"}),
    ],
)
def test_invalid_type_specific_geometry_is_rejected(kind: str, params: dict[str, object]) -> None:
    with pytest.raises((ValueError, ValidationError)):
        parse_cad_design(json.dumps({"components": [component("cmp_1", kind, params)]}))


@pytest.mark.parametrize(
    "invalid",
    [
        {"id": " ", "type": "microstrip", "x": 0, "y": 0, "rotation": 0},
        {"id": "cmp_1", "type": "unknown", "x": 0, "y": 0, "rotation": 0},
        {
            "id": "cmp_1",
            "type": "microstrip",
            "x": True,
            "y": 0,
            "rotation": 0,
            "params": {},
        },
        {
            "id": "cmp_1",
            "type": "microstrip",
            "x": 1e999,
            "y": 0,
            "rotation": 0,
            "params": {},
        },
        {
            "id": "cmp_1",
            "type": "microstrip",
            "x": 0,
            "y": 0,
            "rotation": 0,
            "params": {"nested": float("nan")},
        },
    ],
)
def test_malformed_components_fail_closed(invalid: dict[str, object]) -> None:
    with pytest.raises((ValueError, ValidationError)):
        parse_cad_design(json.dumps({"components": [invalid]}))


def test_duplicate_component_ids_rejected() -> None:
    item = component("cmp_same", "microstrip", {"W": 0.5, "L": 5})
    with pytest.raises(ValueError, match="unique"):
        parse_cad_design(json.dumps({"components": [item, item]}))


@pytest.mark.parametrize(
    "substrate",
    [
        {"h": 0},
        {"er": 0.99},
        {"tanD": -0.01},
        {"tanD": 1.01},
        {"t": -1},
        {"er": "3.55"},
        {"h": True},
    ],
)
def test_invalid_substrate_values_rejected(substrate: dict[str, object]) -> None:
    with pytest.raises((ValueError, ValidationError)):
        parse_cad_design(json.dumps({"substrate": substrate, "components": []}))


@pytest.mark.parametrize("text", ["[] trailing", "{bad", "NaN", "null", '"root"'])
def test_non_document_json_roots_rejected(text: str) -> None:
    with pytest.raises(ValueError):
        parse_cad_design(text)


@pytest.mark.parametrize(
    "text",
    [
        '{"components":[{"id":"a","id":"b"}]}',
        '{"components":[{"id":"a","type":"microstrip","x":NaN,"y":0,"rotation":0}]}',
        '{"components":[{"id":"a","type":"microstrip","x":1e999,"y":0,"rotation":0}]}',
    ],
)
def test_duplicate_keys_and_nonfinite_numbers_rejected(text: str) -> None:
    with pytest.raises(ValueError, match="Invalid RF CAD JSON"):
        parse_cad_design(text)


def test_unknown_top_level_document_versions_are_rejected() -> None:
    with pytest.raises(ValueError, match="version"):
        parse_cad_design(json.dumps({"version": "2.0", "components": []}))


def test_legacy_bare_component_array_is_accepted_and_normalized() -> None:
    bare = [component("cmp_1", "via", {"drill": 0.2, "pad": 0.5})]
    parsed = parse_cad_design(json.dumps(bare))
    assert parsed.version == "1.0"
    assert parsed.substrate is None
    assert json.loads(serialize_cad_design(parsed))["version"] == "1.0"


def test_oversized_json_rejected_before_model_validation() -> None:
    with pytest.raises(ValueError, match="5 MiB"):
        parse_cad_design(" " * (MAX_CAD_BYTES + 1))


def test_serialized_cad_document_size_is_bounded() -> None:
    design = CADDesign.model_validate(
        {"components": [component("cmp_1", "microstrip", {"W": 0.5, "L": 5})]}
    )
    design.extra_note = "x" * MAX_CAD_BYTES
    with pytest.raises(ValueError, match="5 MiB"):
        serialize_cad_design(design)


def test_file_reader_enforces_utf8_and_size_limits(tmp_path: Path) -> None:
    invalid = tmp_path / "invalid.json"
    invalid.write_bytes(b"\xff\xfe")
    with pytest.raises(ValueError, match="UTF-8"):
        read_cad_design(invalid)
    oversized = tmp_path / "oversized.json"
    oversized.write_bytes(b" " * (MAX_CAD_BYTES + 1))
    with pytest.raises(ValueError, match="5 MiB"):
        read_cad_design(oversized)


def test_file_reader_parses_and_preserves_legacy_design(tmp_path: Path) -> None:
    source = tmp_path / "rf-cad.json"
    source.write_text(json.dumps(legacy_document()), encoding="utf-8")
    parsed = read_cad_design(source)
    assert len(parsed.components) == 8
    assert parsed.substrate is not None
    assert parsed.substrate.er == 3.55
