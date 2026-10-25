import json
from pathlib import Path

import pytest
from pydantic import JsonValue, ValidationError

from rfview.domain import cad
from rfview.domain.cad import (
    MAX_CAD_BYTES,
    MAX_CAD_HISTORY_STATES,
    CADComponent,
    CADDesign,
    CADHistory,
    cad_dimensions,
    parse_cad_design,
    serialize_cad_design,
    update_cad_dimensions,
    update_cad_placement,
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


def test_placement_edit_is_pure_and_preserves_other_fields() -> None:
    design = parse_cad_design(json.dumps(legacy_document()))
    original = design.model_dump(mode="json")
    updated = update_cad_placement(
        design, "cmp_1", name="Moved feed", x=-12.5, y=6.75, rotation=90, layer="metal_bot"
    )
    assert design.model_dump(mode="json") == original
    expected = json.loads(json.dumps(original))
    expected["components"][0].update(
        name="Moved feed", x=-12.5, y=6.75, rotation=90, layer="metal_bot"
    )
    assert updated.model_dump(mode="json") == expected
    assert parse_cad_design(serialize_cad_design(updated)) == updated
    updated.components[1].params["W"] = 10
    assert design.components[1].params["W"] == 0.6


@pytest.mark.parametrize(
    ("x", "y", "rotation"),
    [
        (1_000_001, 0, 0),
        (0, -1_000_001, 0),
        (float("nan"), 0, 0),
        (0, float("inf"), 0),
        (0, 0, 360_001),
        (0, 0, float("inf")),
        (True, 0, 0),
    ],
)
def test_invalid_placement_edit_retains_source(x: float, y: float, rotation: float) -> None:
    design = parse_cad_design(json.dumps(legacy_document()))
    original = design.model_dump(mode="json")
    with pytest.raises(ValueError):
        update_cad_placement(
            design, "cmp_1", name="Rejected", x=x, y=y, rotation=rotation, layer="metal_top"
        )
    assert design.model_dump(mode="json") == original


def test_placement_edit_rejects_missing_component_and_oversized_text() -> None:
    design = parse_cad_design(json.dumps(legacy_document()))
    with pytest.raises(ValueError, match="not in the current"):
        update_cad_placement(design, "absent", name="", x=0, y=0, rotation=0, layer="metal_top")
    with pytest.raises(ValueError):
        update_cad_placement(
            design, "cmp_1", name="x" * 201, x=0, y=0, rotation=0, layer="metal_top"
        )
    with pytest.raises(ValueError):
        update_cad_placement(design, "cmp_1", name="", x=0, y=0, rotation=0, layer="x" * 101)


@pytest.mark.parametrize("index", range(8))
def test_dimension_edit_for_each_type_preserves_all_other_data(index: int) -> None:
    design = parse_cad_design(json.dumps(legacy_document()))
    before = design.model_dump(mode="json")
    selected = design.components[index]
    changes: dict[str, JsonValue] = {
        key: value * 1.5 for key, value in cad_dimensions(selected).items()
    }
    updated = update_cad_dimensions(design, selected.id, changes)
    expected = json.loads(json.dumps(before))
    expected["components"][index]["params"].update(changes)
    assert updated.model_dump(mode="json") == expected
    assert design.model_dump(mode="json") == before
    assert parse_cad_design(serialize_cad_design(updated)) == updated
    updated.components[0].params["vendor_param"] = "Changed only in new document"
    assert design.components[0].params["vendor_param"] == "x"


def test_dimension_edit_preserves_palette_alias_and_supports_partial_updates() -> None:
    design = parse_cad_design(json.dumps([component("alias", "ms", {"W": 0.5, "L": 5})]))
    updated = update_cad_dimensions(design, "alias", {"W": 0.75})
    assert updated.components[0].type == "ms"
    assert cad_dimensions(updated.components[0]) == {"W": 0.75, "L": 5}


@pytest.mark.parametrize(
    "changes",
    [
        {},
        {"vendor_param": "overwrite"},
        {"W": 0.7, "gap": 0.2},
        {"W": 0},
        {"L": -1},
        {"W": None},
        {"L": "4"},
        {"W": True},
        {"W": float("nan")},
        {"W": float("inf")},
        {"W": [1]},
        {"miter": False},
        {"portNum": 2},
        {"type": "via"},
    ],
)
def test_dimension_edit_rejects_invalid_values_or_unsupported_fields(
    changes: dict[str, JsonValue],
) -> None:
    design = parse_cad_design(json.dumps(legacy_document()))
    before = serialize_cad_design(design)
    with pytest.raises(ValueError):
        update_cad_dimensions(design, "cmp_1", changes)
    assert serialize_cad_design(design) == before


def test_dimension_edit_rejects_unknown_target() -> None:
    design = parse_cad_design(json.dumps(legacy_document()))
    with pytest.raises(ValueError, match="not in the current"):
        update_cad_dimensions(design, "missing", {"W": 0.7})


def test_cad_history_restores_placement_dimensions_and_vendor_data() -> None:
    original = parse_cad_design(json.dumps(legacy_document()))
    placed = update_cad_placement(
        original, "cmp_1", name="Moved", x=4, y=6, rotation=90, layer="metal_bot"
    )
    resized = update_cad_dimensions(placed, "cmp_2", {"W": 0.75})
    initial = CADHistory.from_design(original)
    history = initial.record(placed).record(resized)
    assert (history.undo_count, history.redo_count) == (2, 0)
    undone = history.undo()
    assert undone.current_text == serialize_cad_design(placed)
    assert (undone.undo_count, undone.redo_count) == (1, 1)
    assert undone.undo().current_text == serialize_cad_design(original)
    assert undone.redo() == history
    assert initial.current_text == serialize_cad_design(original)
    assert initial.undo_count == 0
    restored = parse_cad_design(history.current_text)
    restored.components[0].params["vendor_param"] = "modified after restore"
    resized.components[0].params["vendor_param"] = "modified after record"
    assert parse_cad_design(history.current_text).components[0].params["vendor_param"] == "x"
    assert parse_cad_design(initial.current_text).components[0].params["vendor_param"] == "x"


def test_cad_history_branching_noop_and_rejected_edits() -> None:
    original = parse_cad_design(json.dumps(legacy_document()))
    resized = update_cad_dimensions(original, "cmp_1", {"L": 8})
    history = CADHistory.from_design(original).record(resized).undo()
    assert history.record(original) is history
    assert history.record(update_cad_dimensions(original, "cmp_1", {"L": 5.0})) is history
    with pytest.raises(ValueError):
        history.record(update_cad_dimensions(original, "cmp_1", {"L": -1}))
    assert history.redo().current_text == serialize_cad_design(resized)
    branched = history.record(update_cad_dimensions(original, "cmp_1", {"L": 10}))
    assert branched.redo_count == 0
    assert branched.undo().current_text == serialize_cad_design(original)
    with pytest.raises(ValueError, match="No CAD edit"):
        branched.redo()
    with pytest.raises(ValueError, match="No CAD edit"):
        branched.undo().undo()


def test_cad_history_rejects_invalid_or_oversized_documents() -> None:
    original = parse_cad_design(json.dumps(legacy_document()))
    history = CADHistory.from_design(original)
    original.components[0].params["W"] = -1
    with pytest.raises(ValueError):
        history.record(original)
    assert history.undo_count == 0
    oversized = parse_cad_design(json.dumps(legacy_document()))
    oversized.components[0].params["vendor"] = "x" * MAX_CAD_BYTES
    with pytest.raises(ValueError, match="5 MiB"):
        history.record(oversized)
    with pytest.raises(ValueError):
        CADHistory.from_design(oversized)
    assert history.redo_count == 0


def test_cad_history_caps_retained_state_count_and_can_traverse_remaining_states() -> None:
    original = parse_cad_design(json.dumps(legacy_document()))
    history = CADHistory.from_design(original)
    for length in range(1, MAX_CAD_HISTORY_STATES + 3):
        history = history.record(update_cad_dimensions(original, "cmp_1", {"L": length}))
    assert history.undo_count == MAX_CAD_HISTORY_STATES - 1
    latest = history.current_text
    for _ in range(MAX_CAD_HISTORY_STATES - 1):
        history = history.undo()
    assert parse_cad_design(history.current_text).components[0].params["L"] == 3
    assert history.redo_count == MAX_CAD_HISTORY_STATES - 1
    for _ in range(MAX_CAD_HISTORY_STATES - 1):
        history = history.redo()
    assert history.current_text == latest


def test_cad_history_caps_utf8_bytes_including_current_and_redo(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    design = parse_cad_design(json.dumps(legacy_document()))
    design.components[0].params["vendor"] = "\u03bb" * 100
    serialized = serialize_cad_design(design)
    byte_limit = 2 * len(serialized.encode("utf-8"))
    monkeypatch.setattr(cad, "MAX_CAD_HISTORY_BYTES", byte_limit)
    history = CADHistory.from_design(design)
    for length in (6, 7, 8):
        history = history.record(update_cad_dimensions(design, "cmp_1", {"L": length}))
    assert history.size_bytes <= byte_limit
    assert history.undo_count == 1
    assert history.size_bytes == len(history.current_text.encode("utf-8")) + len(
        history.undo().current_text.encode("utf-8")
    )
    assert history.undo().size_bytes == history.size_bytes
    assert parse_cad_design(history.undo().current_text).components[0].params["L"] == 7


def test_cad_history_imported_empty_design_has_no_undo_or_redo() -> None:
    history = CADHistory.from_design(CADDesign())
    assert (history.undo_count, history.redo_count) == (0, 0)
    for action in (history.undo, history.redo):
        with pytest.raises(ValueError, match="No CAD edit"):
            action()


def test_cad_history_distinguishes_json_boolean_from_numeric_vendor_values() -> None:
    design = parse_cad_design(json.dumps(legacy_document()))
    design.components[0].params["vendor_flag"] = True
    history = CADHistory.from_design(design)
    design.components[0].params["vendor_flag"] = 1
    changed = history.record(design)
    assert changed.undo_count == 1
    assert parse_cad_design(changed.current_text).components[0].params["vendor_flag"] == 1
    assert parse_cad_design(changed.undo().current_text).components[0].params["vendor_flag"] is True
