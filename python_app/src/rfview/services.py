import json
from pathlib import Path

import yaml

from rfview.domain.guardrails import GuardrailCatalog
from rfview.domain.models import CanvasWorkspace, LineupDocument, OperatingPoint
from rfview.domain.touchstone import (
    MAX_TOUCHSTONE_BYTES,
    TouchstoneData,
    parse_touchstone,
)

MAX_DOCUMENT_BYTES = 5 * 1024 * 1024


def read_touchstone(
    path: Path, dataset_tag: str | None = None, *, filename: str | None = None
) -> TouchstoneData:
    if path.stat().st_size > MAX_TOUCHSTONE_BYTES:
        raise ValueError("Touchstone exceeds the 5 MiB migration limit")
    return parse_touchstone(
        path.read_text(encoding="utf-8-sig"), filename or path.name, dataset_tag
    )


def read_guardrails(path: Path) -> GuardrailCatalog:
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8-sig"))
    except yaml.YAMLError as exc:
        raise ValueError(f"Invalid technology guardrail YAML at {path}: {exc}") from exc
    return GuardrailCatalog.model_validate(raw)


def parse_document(text: str) -> LineupDocument:
    if len(text.encode("utf-8")) > MAX_DOCUMENT_BYTES:
        raise ValueError("Lineup JSON exceeds the 5 MiB migration limit")
    return LineupDocument.model_validate_json(text)


def read_document(path: Path) -> LineupDocument:
    if path.stat().st_size > MAX_DOCUMENT_BYTES:
        raise ValueError("Lineup JSON exceeds the 5 MiB migration limit")
    return parse_document(path.read_text(encoding="utf-8-sig"))


def read_workspace(path: Path) -> CanvasWorkspace:
    if path.stat().st_size > MAX_DOCUMENT_BYTES:
        raise ValueError("Workspace JSON exceeds the 5 MiB migration limit")
    return CanvasWorkspace.model_validate_json(path.read_text(encoding="utf-8-sig"))


def serialize_workspace(workspace: CanvasWorkspace) -> str:
    text = json.dumps(workspace.model_dump(mode="json", by_alias=True), indent=2, allow_nan=False)
    if len(text.encode("utf-8")) > MAX_DOCUMENT_BYTES:
        raise ValueError("Workspace JSON exceeds the 5 MiB migration limit")
    return text


def serialize_document(document: LineupDocument) -> str:
    return json.dumps(document.model_dump(mode="json", by_alias=True), indent=2, allow_nan=False)


def example_document() -> LineupDocument:
    return read_document(Path(__file__).parent / "examples" / "branched.json")


def operating_point(document: LineupDocument) -> OperatingPoint | None:
    saved = document.metadata.get("python_operating_point")
    return None if saved is None else OperatingPoint.model_validate(saved)


def with_operating_point(document: LineupDocument, point: OperatingPoint) -> LineupDocument:
    saved = document.model_copy(deep=True)
    saved.metadata["python_operating_point"] = point.model_dump(mode="json")
    return saved
