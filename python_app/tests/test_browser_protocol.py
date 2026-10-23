import json

import pytest

from rfview.app import BrowserAction
from rfview.domain.models import LineupDocument


def test_frozen_shiny_json_arrays_are_restored_at_protocol_boundary() -> None:
    snapshot = {
        "components": (
            {
                "id": 1,
                "type": "matching",
                "properties": {"display": ("label", "loss")},
            },
        ),
        "connections": (),
        "metadata": {"nested": {"arrays": (1, (2, 3))}},
    }
    document = LineupDocument.model_validate_json(json.dumps(snapshot))
    assert document.components[0].properties["display"] == ["label", "loss"]
    assert document.metadata["nested"] == {"arrays": [1, [2, 3]]}
    action = BrowserAction.model_validate_json(
        json.dumps(
            {
                "action": "compare_workspace",
                "request_id": 1,
                "document": snapshot,
                "workspace": {
                    "active": "1",
                    "canvases": {str(i): snapshot for i in range(1, 5)},
                },
            }
        )
    )
    assert action.workspace is not None
    assert action.workspace.canvases["1"].components[0].properties["display"] == ["label", "loss"]


def test_json_boundary_still_rejects_nonfinite_or_invalid_documents() -> None:
    with pytest.raises(ValueError):
        LineupDocument.model_validate_json(
            json.dumps(
                {
                    "components": [
                        {"id": 1, "type": "matching", "properties": {"loss": float("nan")}}
                    ],
                }
            )
        )
