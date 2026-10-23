from __future__ import annotations

import math
from collections import deque
from typing import Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    JsonValue,
    StrictInt,
    StrictStr,
    field_validator,
    model_validator,
)

ComponentType = Literal[
    "transistor", "matching", "splitter", "combiner", "offset_line", "termination"
]


def finite(value: float, name: str) -> float:
    if not math.isfinite(value):
        raise ValueError(f"{name} must be finite")
    return value


def positive(value: float, name: str) -> float:
    finite(value, name)
    if value <= 0:
        raise ValueError(f"{name} must be greater than zero")
    return value


def nonnegative(value: float, name: str) -> float:
    finite(value, name)
    if value < 0:
        raise ValueError(f"{name} must not be negative")
    return value


def _check_json(value: JsonValue) -> None:
    if isinstance(value, float):
        finite(value, "JSON numeric value")
    elif isinstance(value, dict):
        for item in value.values():
            _check_json(item)
    elif isinstance(value, list):
        for item in value:
            _check_json(item)


class Component(BaseModel):
    model_config = ConfigDict(extra="allow", allow_inf_nan=False)

    id: StrictInt | StrictStr
    type: ComponentType
    x: float = 0
    y: float = 0
    properties: dict[str, JsonValue] = Field(default_factory=dict)

    @field_validator("id")
    @classmethod
    def valid_id(cls, value: int | str) -> int | str:
        if isinstance(value, str) and not value.strip():
            raise ValueError("Component ID must not be empty")
        if isinstance(value, int) and abs(value) > 2**53 - 1:
            raise ValueError("Numeric IDs must be exactly representable in JavaScript")
        return value

    def number(self, key: str, default: float) -> float:
        value = self.properties.get(key)
        if value is None:
            return finite(default, key)
        if isinstance(value, bool) or not isinstance(value, (int, float, str)):
            raise ValueError(f"Component {self.id}: {key} must be numeric")
        try:
            return finite(float(value), f"Component {self.id}: {key}")
        except ValueError as exc:
            raise ValueError(f"Component {self.id}: invalid {key}: {value!r}") from exc

    def text(self, key: str, default: str = "") -> str:
        value = self.properties.get(key)
        if value is None:
            return default
        if not isinstance(value, str):
            raise ValueError(f"Component {self.id}: {key} must be text")
        return value


class Connection(BaseModel):
    model_config = ConfigDict(extra="allow", populate_by_name=True)

    from_id: StrictInt | StrictStr = Field(alias="from")
    to: StrictInt | StrictStr


class LineupDocument(BaseModel):
    model_config = ConfigDict(extra="allow", allow_inf_nan=False)

    schema_version: Literal["1.0"] = "1.0"
    components: list[Component] = Field(max_length=2000)
    connections: list[Connection] = Field(default_factory=list, max_length=10000)
    metadata: dict[str, JsonValue] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_document(self) -> LineupDocument:
        _check_json(self.model_dump(mode="json", by_alias=True))
        ids = [str(component.id) for component in self.components]
        if len(ids) != len(set(ids)):
            raise ValueError("Component IDs must be unique, including numeric/string equivalents")
        known = set(ids)
        seen: set[tuple[str, str]] = set()
        for edge in self.connections:
            pair = (str(edge.from_id), str(edge.to))
            if not set(pair) <= known:
                raise ValueError(f"Connection references a missing component: {pair}")
            if pair[0] == pair[1]:
                raise ValueError("Self-connections are not supported")
            if pair in seen:
                raise ValueError(f"Duplicate connection: {pair}")
            seen.add(pair)
        self.ordered_components()
        return self

    def ordered_components(self) -> list[Component]:
        if not self.connections:
            return sorted(self.components, key=lambda component: component.x)
        lookup = {str(component.id): component for component in self.components}
        predecessors, successors = self.graph()
        degree = {key: len(predecessors[key]) for key in lookup}
        queue = deque(
            sorted((key for key in lookup if degree[key] == 0), key=lambda key: lookup[key].x)
        )
        ordered: list[Component] = []
        while queue:
            key = queue.popleft()
            ordered.append(lookup[key])
            available = []
            for successor in successors[key]:
                degree[successor] -= 1
                if degree[successor] == 0:
                    available.append(successor)
            queue.extend(sorted(available, key=lambda item: lookup[item].x))
        if len(ordered) != len(lookup):
            raise ValueError("Connection graph contains a cycle")
        return ordered

    def graph(self) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
        predecessors: dict[str, list[str]] = {
            str(component.id): [] for component in self.components
        }
        successors: dict[str, list[str]] = {str(component.id): [] for component in self.components}
        for edge in self.connections:
            predecessors[str(edge.to)].append(str(edge.from_id))
            successors[str(edge.from_id)].append(str(edge.to))
        return predecessors, successors


class StageResult(BaseModel):
    id: str
    stage: str
    type: ComponentType
    pin_dbm: float
    pout_dbm: float
    pin_bo_dbm: float
    pout_bo_dbm: float
    gain_full_db: float
    gain_bo_db: float
    gain_db: float | None = None
    pae_pct: float | None = None
    de_pct: float | None = None
    pdc_w: float | None = None
    pdiss_w: float | None = None
    idc_a: float | None = None
    tj_c: float | None = None
    compressed: bool | None = None
    technology: str | None = None
    pae_bo_pct: float | None = None
    de_bo_pct: float | None = None
    pdc_bo_w: float | None = None
    pdiss_bo_w: float | None = None
    tj_bo_c: float | None = None
    compressed_bo: bool | None = None
    loss_db: float | None = None
    split_loss_db: float | None = None
    n_outputs: int | None = None
    split_ratio: float | None = None
    n_inputs: int | None = None
    phase_shift_deg: float | None = None
    impedance: float | None = None
    offset_role: str | None = None


class PhaseResult(BaseModel):
    stage: str
    type: ComponentType
    phase_contrib: float
    cumulative_phase: float
    notes: str = ""


class LineupResult(BaseModel):
    success: Literal[True] = True
    model_version: str = "legacy-r-v1"
    backoff_db: float
    input_power_dbm: float
    final_pout_dbm: float
    final_pout_w: float
    total_gain: float
    net_gain_db: float
    total_pdc: float
    system_pae: float
    system_de: float
    total_pdiss: float
    final_pout_bo_dbm: float
    final_pout_bo_w: float
    total_pdc_bo: float
    system_pae_bo: float
    system_de_bo: float
    total_pdiss_bo: float
    stage_results: list[StageResult]
    phase_results: list[PhaseResult]
    warnings: list[str]
    rationale: str


class OperatingPoint(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    input_power_dbm: float = Field(default=20, ge=-100, le=100)
    backoff_db: float = Field(default=6, ge=0, le=60)
    architecture: Literal["conventional", "doherty"] = "doherty"
    use_canvas_operating_points: bool = False
