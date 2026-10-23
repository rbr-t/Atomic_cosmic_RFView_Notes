"""Editable calculation inputs; unrelated legacy properties are preserved."""

from typing import NamedTuple

from pydantic import JsonValue

from rfview.domain.models import Component, finite


class NumericProperty(NamedTuple):
    key: str
    label: str
    default: float


def property_fields(component: Component) -> tuple[NumericProperty, ...]:
    if component.type == "transistor":
        gain = component.number("gain", 15)
        full = component.number("gain_p3db", gain - 2)
        return (
            NumericProperty("gain", "Small-signal gain (dB)", gain),
            NumericProperty("gain_p3db", "Full-power gain (dB)", full),
            NumericProperty("gain_bo", "Backoff gain (dB)", (gain + full) / 2),
            NumericProperty("pae", "Entered efficiency (%)", 50),
            NumericProperty("p1db", "P1dB limit (dBm)", 43),
            NumericProperty("vdd", "Supply voltage (V)", 28),
            NumericProperty("rth", "Thermal resistance (C/W)", 2.5),
        )
    if component.type == "termination":
        return ()
    loss = {"matching": 0.5, "offset_line": 0.2}.get(component.type, 0.3)
    fields: tuple[NumericProperty, ...] = (NumericProperty("loss", "Insertion loss (dB)", loss),)
    if component.type == "offset_line":
        fields += (
            NumericProperty("phase_shift_deg", "Phase shift (deg)", 90),
            NumericProperty("impedance", "Characteristic impedance (ohm)", 50),
        )
    return fields


def validated_properties(
    component: Component, values: dict[str, JsonValue]
) -> dict[str, JsonValue]:
    expected = {field.key for field in property_fields(component)}
    if values.keys() != expected:
        raise ValueError("Property fields do not match the selected component type")
    result: dict[str, JsonValue] = {}
    for key, value in values.items():
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"{key} must be a finite number; blank values are not accepted")
        finite(value, key)
        if key in ("loss", "rth") and value < 0:
            raise ValueError(f"{key} must not be negative")
        if key in ("vdd", "impedance", "pae") and value <= 0:
            raise ValueError(f"{key} must be greater than zero")
        if key == "pae" and value > 100:
            raise ValueError("Entered efficiency must not exceed 100 %")
        result[key] = value
    return result
