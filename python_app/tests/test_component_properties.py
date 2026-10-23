import pytest

from rfview.domain.component_properties import property_fields, validated_properties
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
