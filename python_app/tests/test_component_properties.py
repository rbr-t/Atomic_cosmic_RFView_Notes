import pytest

from rfview.domain.component_properties import (
    ComponentGeometry,
    property_fields,
    text_fields,
    validated_design_properties,
    validated_properties,
)
from rfview.domain.models import Component


@pytest.mark.parametrize(
    "kind", ["transistor", "matching", "splitter", "combiner", "offset_line", "termination"]
)
def test_field_defaults_validate_without_mutating_other_properties(kind: str) -> None:
    component = Component.model_validate({"id": 10, "type": kind, "properties": {"custom": "kept"}})
    before = component.model_dump()
    fields = property_fields(component)
    values = {field.key: field.default for field in fields}
    assert validated_properties(component, values) == values
    assert component.model_dump() == before


@pytest.mark.parametrize(
    "key,value",
    [
        ("loss", -1),
        ("loss", None),
        ("loss", True),
        ("loss", float("nan")),
        ("loss", "2"),
        ("impedance", 0),
        ("impedance", -50),
        ("phase_shift_deg", float("inf")),
    ],
)
def test_invalid_passive_edit_rejected(key: str, value: object) -> None:
    component = Component(id=1, type="offset_line")
    values = {"loss": 0.2, "phase_shift_deg": 90, "impedance": 50, key: value}
    with pytest.raises(ValueError):
        validated_properties(component, values)


@pytest.mark.parametrize("key,value", [("pae", 0), ("pae", 101), ("vdd", 0), ("rth", -1)])
def test_invalid_transistor_edit_rejected(key: str, value: float) -> None:
    component = Component(id=1, type="transistor")
    values = {field.key: field.default for field in property_fields(component)}
    values[key] = value
    with pytest.raises(ValueError):
        validated_properties(component, values)


def test_mismatched_form_rejected_and_transistor_derived_defaults_retained() -> None:
    component = Component(id=1, type="transistor", properties={"gain": 20, "gain_p3db": 16})
    fields = {field.key: field.default for field in property_fields(component)}
    assert fields["gain_bo"] == 18
    with pytest.raises(ValueError, match="selected component type"):
        validated_properties(component, {"loss": 1})


@pytest.mark.parametrize(
    "kind",
    [
        "transistor",
        "matching",
        "splitter",
        "combiner",
        "offset_line",
        "termination",
    ],
)
def test_design_properties_are_explicit_nonmutating_and_preserve_text(kind: str) -> None:
    component = Component.model_validate(
        {
            "id": 1,
            "type": kind,
            "properties": {"custom": "retained"},
        }
    )
    before = component.model_dump()
    values = {
        key: "phase" if key == "offset_role" else "Device 1" for key in text_fields(component)
    }
    assert validated_design_properties(component, values) == values
    assert component.model_dump() == before
    with pytest.raises(ValueError, match="fields"):
        validated_design_properties(component, {"unexpected": ""})
    values["label"] = "x" * 201
    with pytest.raises(ValueError, match="200"):
        validated_design_properties(component, values)


@pytest.mark.parametrize(
    "changes",
    [
        {"x": 1e7},
        {"rotation": 361},
        {"y": float("nan")},
        {"flipH": 1},
        {"flipV": "yes"},
        {"x": True},
    ],
)
def test_invalid_design_geometry_rejected(changes: dict) -> None:
    with pytest.raises(ValueError):
        ComponentGeometry.model_validate(
            {
                "x": 1,
                "y": 2,
                "rotation": 0,
                "flipH": False,
                "flipV": False,
                **changes,
            }
        )


@pytest.mark.parametrize("value", [None, 123, True, "bad\nlabel"])
def test_invalid_metadata_is_not_silently_coerced(value) -> None:
    component = Component(id=1, type="termination")
    with pytest.raises(ValueError, match="text"):
        validated_design_properties(component, {"label": value})


def test_offset_role_metadata_rejects_unknown_behavior() -> None:
    component = Component(id=1, type="offset_line")
    with pytest.raises(ValueError, match="phase or inverter"):
        validated_design_properties(component, {"label": "Offset", "offset_role": "unknown"})
