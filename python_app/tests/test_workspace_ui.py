from rfview.domain.models import CanvasWorkspace, Component, LineupDocument, OperatingPoint
from rfview.services import example_document
from rfview.workspace_ui import workspace_comparison


def test_workspace_comparison_is_nonmutating_and_labels_units_and_empty_slots() -> None:
    workspace = CanvasWorkspace(
        active="1",
        canvases={
            "1": example_document(),
            "2": example_document(),
            "3": LineupDocument(components=[]),
            "4": LineupDocument(components=[]),
        },
    )
    workspace.canvases["2"].components[1].properties["gain_p3db"] = 10
    before = workspace.model_dump()
    html = str(workspace_comparison(workspace, OperatingPoint()))
    assert html.count('class="comparison-card"') == 4
    assert html.count("<svg") == 2
    assert "35.400 dBm" in html
    assert "net gain:" in html and "DC:" in html and "PAE:" in html
    assert "Empty canvas; no calculation" in html
    assert "legacy-r-v1" in html
    assert workspace.model_dump() == before


def test_invalid_canvas_has_explicit_error_not_invented_numeric_result(caplog) -> None:
    bad = LineupDocument(
        components=[
            Component(
                id=1, type="offset_line", properties={"loss": "invalid", "label": "<script>"}
            ),
        ]
    )
    workspace = CanvasWorkspace(
        active="1",
        canvases={
            "1": bad,
            **{str(i): LineupDocument(components=[]) for i in range(2, 5)},
        },
    )
    html = str(workspace_comparison(workspace, OperatingPoint()))
    assert "Calculation rejected for canvas 1" in html
    assert "<script>" not in html and "&lt;script&gt;" in html
    assert "Output:" not in html
    assert "canvas 1 rejected" in caplog.text


def test_independent_operating_point_comparisons() -> None:
    workspace = CanvasWorkspace(
        active="1",
        canvases={str(i): example_document() for i in range(1, 5)},
    )
    first = str(workspace_comparison(workspace, OperatingPoint(input_power_dbm=10)))
    second = str(workspace_comparison(workspace, OperatingPoint(input_power_dbm=20)))
    assert first != second
    assert "Shared input 10 dBm" in first and "Shared input 20 dBm" in second


def test_large_comparison_does_not_silently_decimate_geometry() -> None:
    document = LineupDocument(
        components=[
            Component(id=i, type="matching", x=i, properties={"loss": 0}) for i in range(201)
        ]
    )
    workspace = CanvasWorkspace(
        active="1",
        canvases={
            "1": document,
            **{str(i): LineupDocument(components=[]) for i in range(2, 5)},
        },
    )
    html = str(workspace_comparison(workspace, OperatingPoint()))
    assert "overview limit is 200 components" in html
    assert "<svg" not in html
    assert "Output: 20.000 dBm" in html
