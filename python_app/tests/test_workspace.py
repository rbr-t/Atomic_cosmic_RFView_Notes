import json
from pathlib import Path

import pytest

from rfview.domain.models import CanvasWorkspace, LineupDocument
from rfview.services import example_document, read_workspace, serialize_workspace


def test_four_slot_workspace_roundtrip_and_independent_ids(tmp_path: Path) -> None:
    document = example_document()
    workspace = CanvasWorkspace(
        active="2",
        canvases={
            "1": document,
            "2": document.model_copy(deep=True),
            "3": LineupDocument(components=[]),
            "4": LineupDocument(components=[]),
        },
    )
    before = workspace.model_dump()
    path = tmp_path / "workspace.json"
    path.write_text(serialize_workspace(workspace), encoding="utf-8")
    result = read_workspace(path)
    assert result.model_dump() == before
    result.canvases["2"].components[0].properties["loss"] = 1
    assert result.canvases["1"].components[0].number("loss", 0) == 0.3


@pytest.mark.parametrize(
    "changes",
    [
        {"active": "5"},
        {"format": "other"},
        {"canvases": {"1": {"components": []}}},
        {"canvases": {str(i): {"components": []} for i in range(4)}},
        {"canvases": {str(i): {"components": [{"id": 1, "type": "other"}]} for i in range(1, 5)}},
    ],
)
def test_invalid_workspace_is_explicit(changes: dict, tmp_path: Path) -> None:
    data = {
        "format": "rfview-workspace-v1",
        "active": "1",
        "canvases": {str(i): {"components": []} for i in range(1, 5)},
        **changes,
    }
    path = tmp_path / "invalid.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(ValueError):
        read_workspace(path)


def test_workspace_limits_apply_to_input_and_output(tmp_path: Path) -> None:
    path = tmp_path / "large.json"
    path.write_bytes(b" " * (5 * 1024 * 1024 + 1))
    with pytest.raises(ValueError, match="5 MiB"):
        read_workspace(path)
    workspace = CanvasWorkspace(
        active="1", canvases={str(i): LineupDocument(components=[]) for i in range(1, 5)}
    )
    workspace.canvases["1"].metadata["large"] = "x" * (5 * 1024 * 1024)
    with pytest.raises(ValueError, match="5 MiB"):
        serialize_workspace(workspace)
