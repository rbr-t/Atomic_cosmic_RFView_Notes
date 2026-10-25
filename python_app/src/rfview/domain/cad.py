"""Bounded RF CAD document contract for the legacy JSON interchange format."""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    JsonValue,
    StringConstraints,
    field_validator,
    model_validator,
)

CADComponentType = Literal[
    "microstrip",
    "ms",
    "bend90",
    "tee",
    "coupled",
    "via",
    "port",
    "open_stub",
    "short_stub",
]

CADId = Annotated[
    str,
    StringConstraints(min_length=1, max_length=100),
]
MAX_CAD_BYTES = 5 * 1024 * 1024
MAX_CAD_COMPONENTS = 10_000
MAX_CAD_POSITION_MM = 1_000_000
MAX_CAD_HISTORY_STATES = 20
MAX_CAD_HISTORY_BYTES = 20 * 1024 * 1024
_SAFE_ID = re.compile(r"^[^\x00-\x1f\x7f]+$")

_DIMENSION_FIELDS: dict[CADComponentType, tuple[str, ...]] = {
    "microstrip": ("W", "L"),
    "ms": ("W", "L"),
    "bend90": ("W", "L"),
    "tee": ("W", "L"),
    "coupled": ("W", "L", "gap"),
    "via": ("drill", "pad"),
    "port": ("W",),
    "open_stub": ("W", "L"),
    "short_stub": ("W", "L"),
}


class CADSubstrate(BaseModel):
    model_config = ConfigDict(extra="allow", allow_inf_nan=False)

    h: float | None = Field(default=None, gt=0, allow_inf_nan=False)
    er: float | None = Field(default=None, ge=1, allow_inf_nan=False)
    tanD: float | None = Field(default=None, ge=0, le=1, allow_inf_nan=False)
    t: float | None = Field(default=None, ge=0, allow_inf_nan=False)

    @field_validator("h", "er", "tanD", "t", mode="before")
    @classmethod
    def finite_numeric_input(cls, value: object) -> object:
        if value is None:
            return None
        return _numeric(value, "substrate field")


class CADComponent(BaseModel):
    model_config = ConfigDict(extra="allow", allow_inf_nan=False)

    id: CADId
    type: CADComponentType
    name: Annotated[str, StringConstraints(max_length=200)] = ""
    x: float = Field(ge=-MAX_CAD_POSITION_MM, le=MAX_CAD_POSITION_MM, allow_inf_nan=False)
    y: float = Field(ge=-MAX_CAD_POSITION_MM, le=MAX_CAD_POSITION_MM, allow_inf_nan=False)
    rotation: float = Field(ge=-360_000, le=360_000, allow_inf_nan=False)
    layer: Annotated[str, StringConstraints(max_length=100)] = "metal_top"
    params: dict[str, JsonValue] = Field(default_factory=dict)

    @field_validator("x", "y", "rotation", mode="before")
    @classmethod
    def finite_geometry_input(cls, value: object) -> float:
        return _numeric(value, "component geometry")

    @field_validator("id")
    @classmethod
    def validate_id(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("CAD component identifier must not be blank")
        if not _SAFE_ID.fullmatch(value):
            raise ValueError("CAD component identifier contains control characters")
        return value

    @model_validator(mode="after")
    def validate_geometry_parameters(self) -> CADComponent:
        for key in _DIMENSION_FIELDS[self.type]:
            value = self.params.get(key)
            if value is None:
                raise ValueError(f"CAD parameter {key} is required for {self.type}")
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ValueError(f"CAD parameter {key} must be numeric")
            if not math.isfinite(value) or value <= 0:
                raise ValueError(f"CAD parameter {key} must be finite and greater than zero")
        miter = self.params.get("miter")
        if miter is not None and not isinstance(miter, bool):
            raise ValueError("CAD bend miter parameter must be Boolean")
        port_number = self.params.get("portNum")
        if port_number is not None:
            if isinstance(port_number, bool) or not isinstance(port_number, int) or port_number < 1:
                raise ValueError("CAD port number must be a positive integer")
        return self


class CADDesign(BaseModel):
    model_config = ConfigDict(extra="allow", allow_inf_nan=False)

    version: Literal["1.0"] = "1.0"
    substrate: CADSubstrate | None = None
    components: list[CADComponent] = Field(default_factory=list, max_length=MAX_CAD_COMPONENTS)

    @field_validator("components")
    @classmethod
    def validate_component_ids(cls, components: list[CADComponent]) -> list[CADComponent]:
        ids = [component.id for component in components]
        if len(ids) != len(set(ids)):
            raise ValueError("CAD component IDs must be unique")
        return components


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON object key: {key}")
        result[key] = value
    return result


def _numeric(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"RF CAD {label} must be numeric")
    if not math.isfinite(value):
        raise ValueError(f"RF CAD {label} must be finite")
    return float(value)


def _reject_constant(value: str) -> None:
    raise ValueError(f"Non-finite JSON value is not permitted: {value}")


def _finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"Non-finite JSON number is not permitted: {value}")
    return parsed


def parse_cad_design(text: str) -> CADDesign:
    if len(text.encode("utf-8")) > MAX_CAD_BYTES:
        raise ValueError("RF CAD design exceeds the 5 MiB limit")
    try:
        raw = json.loads(
            text,
            parse_constant=_reject_constant,
            parse_float=_finite_float,
            object_pairs_hook=_unique_object,
        )
    except (json.JSONDecodeError, RecursionError) as exc:
        raise ValueError(f"Invalid RF CAD JSON: {exc}") from exc
    except ValueError as exc:
        raise ValueError(f"Invalid RF CAD JSON: {exc}") from exc
    if isinstance(raw, list):
        # The legacy canvas accepts bare component arrays; normalize them to v1.0.
        raw = {"version": "1.0", "components": raw}
    if not isinstance(raw, dict):
        raise ValueError("RF CAD design must be a versioned object or a legacy component array")
    raw_components = raw.get("components", [])
    if isinstance(raw_components, list) and len(raw_components) > MAX_CAD_COMPONENTS:
        raise ValueError(f"RF CAD design exceeds the {MAX_CAD_COMPONENTS}-component limit")
    try:
        return CADDesign.model_validate(raw)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"Invalid RF CAD design: {exc}") from exc


def serialize_cad_design(design: CADDesign) -> str:
    validated = CADDesign.model_validate_json(design.model_dump_json())
    text = json.dumps(
        validated.model_dump(mode="json", exclude_none=True),
        indent=2,
        ensure_ascii=False,
        allow_nan=False,
    )
    if len(text.encode("utf-8")) > MAX_CAD_BYTES:
        raise ValueError("RF CAD design exceeds the 5 MiB limit")
    return text


def update_cad_placement(
    design: CADDesign,
    component_id: str,
    *,
    name: str,
    x: float,
    y: float,
    rotation: float,
    layer: str,
) -> CADDesign:
    return _update_cad_component(
        design, component_id, dict(name=name, x=x, y=y, rotation=rotation, layer=layer)
    )


def cad_dimensions(component: CADComponent) -> dict[str, float]:
    return {
        key: _numeric(component.params.get(key), f"parameter {key}")
        for key in _DIMENSION_FIELDS[component.type]
    }


def update_cad_dimensions(
    design: CADDesign, component_id: str, dimensions: dict[str, JsonValue]
) -> CADDesign:
    component = next((item for item in design.components if item.id == component_id), None)
    if component is None:
        raise ValueError("Selected component is not in the current CAD document")
    if not dimensions or not dimensions.keys() <= cad_dimensions(component).keys():
        raise ValueError("Only dimension fields supported by the selected CAD type can be edited")
    unchanged_numbers = {
        key: component.params[key]
        for key, value in dimensions.items()
        if not isinstance(value, bool)
        and isinstance(value, (int, float))
        and value == component.params[key]
    }
    return _update_cad_component(
        design, component_id, {"params": component.params | dimensions | unchanged_numbers}
    )


def _update_cad_component(
    design: CADDesign, component_id: str, changes: dict[str, JsonValue]
) -> CADDesign:
    if not any(component.id == component_id for component in design.components):
        raise ValueError("Selected component is not in the current CAD document")
    updated = design.model_dump(mode="json")
    components = []
    for component in design.components:
        data = component.model_dump(mode="json")
        if component.id == component_id:
            data.update(changes)
        components.append(data)
    updated["components"] = components
    return CADDesign.model_validate(updated)


@dataclass(frozen=True)
class CADHistory:
    _states: tuple[str, ...]
    _index: int

    @classmethod
    def from_design(cls, design: CADDesign) -> CADHistory:
        return cls((serialize_cad_design(design),), 0)

    @property
    def current_text(self) -> str:
        return self._states[self._index]

    @property
    def undo_count(self) -> int:
        return self._index

    @property
    def redo_count(self) -> int:
        return len(self._states) - self._index - 1

    @property
    def size_bytes(self) -> int:
        return sum(len(text.encode("utf-8")) for text in self._states)

    def record(self, design: CADDesign) -> CADHistory:
        text = serialize_cad_design(design)
        if text == self.current_text:
            return self
        states = self._states[: self._index + 1] + (text,)
        size = sum(len(state.encode("utf-8")) for state in states)
        while len(states) > MAX_CAD_HISTORY_STATES or size > MAX_CAD_HISTORY_BYTES:
            size -= len(states[0].encode("utf-8"))
            states = states[1:]
        return CADHistory(states, len(states) - 1)

    def undo(self) -> CADHistory:
        if self.undo_count == 0:
            raise ValueError("No CAD edit is available to undo")
        return CADHistory(self._states, self._index - 1)

    def redo(self) -> CADHistory:
        if self.redo_count == 0:
            raise ValueError("No CAD edit is available to redo")
        return CADHistory(self._states, self._index + 1)
