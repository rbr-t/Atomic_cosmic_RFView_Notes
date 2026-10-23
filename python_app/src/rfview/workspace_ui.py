import logging

from shiny import ui

from rfview.domain.lineup import calculate_lineup
from rfview.domain.models import CanvasWorkspace, LineupDocument, OperatingPoint

logger = logging.getLogger(__name__)


def _diagram(document: LineupDocument, slot: str) -> ui.Tag:
    if not document.components:
        return ui.p("Empty canvas; no calculation.")
    if len(document.components) > 200:
        return ui.p(
            "Topology overview limit is 200 components per canvas; "
            "the complete document is still calculated. Use the active canvas for geometry."
        )
    xs = [component.x for component in document.components]
    ys = [component.y for component in document.components]
    left, top = min(xs) - 90, min(ys) - 45
    width, height = max(max(xs) - left + 90, 180), max(max(ys) - top + 45, 90)
    lookup = {str(component.id): component for component in document.components}
    lines = [
        ui.Tag(
            "line",
            x1=lookup[str(edge.from_id)].x,
            y1=lookup[str(edge.from_id)].y,
            x2=lookup[str(edge.to)].x,
            y2=lookup[str(edge.to)].y,
            class_="comparison-edge",
        )
        for edge in document.connections
    ]
    nodes = [
        ui.Tag(
            "g",
            ui.tags.title(f"ID {component.id}: {component.type}"),
            ui.Tag(
                "rect",
                x=component.x - 70,
                y=component.y - 22,
                width=140,
                height=44,
                class_="comparison-node",
            ),
            ui.Tag(
                "text",
                component.text("label", component.type)[:24],
                x=component.x,
                y=component.y + 4,
                text_anchor="middle",
            ),
        )
        for component in document.components
    ]
    return ui.tags.svg(
        ui.tags.title(f"Canvas {slot} topology snapshot"),
        *lines,
        *nodes,
        viewBox=f"{left} {top} {width} {height}",
        role="img",
        **{"aria-label": f"Canvas {slot} topology snapshot"},
    )


def workspace_comparison(workspace: CanvasWorkspace, point: OperatingPoint) -> ui.Tag:
    cards = []
    for slot, document in workspace.canvases.items():
        result_view: ui.Tag
        if not document.components:
            result_view = ui.p("Empty canvas; no calculation.")
        else:
            try:
                result = calculate_lineup(
                    document,
                    point.input_power_dbm,
                    point.backoff_db,
                    point.architecture,
                    use_canvas_operating_points=point.use_canvas_operating_points,
                )
                result_view = ui.div(
                    ui.p(
                        f"Output: {result.final_pout_dbm:.3f} dBm | "
                        f"backoff: {result.final_pout_bo_dbm:.3f} dBm | "
                        f"net gain: {result.net_gain_db:.3f} dB"
                    ),
                    ui.p(
                        f"DC: {result.total_pdc:.3f} W | "
                        f"PAE: {result.system_pae:.3f} % | DE: {result.system_de:.3f} %"
                    ),
                    ui.tags.ul(*(ui.tags.li(warning) for warning in result.warnings)),
                    ui.tags.details(
                        ui.tags.summary("Calculation rationale"), ui.pre(result.rationale)
                    ),
                )
            except (ValueError, OverflowError) as exc:
                logger.warning("Workspace comparison canvas %s rejected: %s", slot, exc)
                result_view = ui.p(f"Calculation rejected for canvas {slot}: {exc}", role="alert")
        cards.append(
            ui.div(
                ui.h3(f"Canvas {slot}"),
                _diagram(document, slot),
                ui.p(
                    f"{len(document.components)} components / "
                    f"{len(document.connections)} connections. "
                    "Read-only topology overview; geometry styling is simplified."
                ),
                result_view,
                class_="comparison-card",
                **{"aria-label": f"Canvas {slot} comparison"},
            )
        )
    return ui.div(
        ui.p(
            "Simultaneous snapshot comparison - legacy-r-v1. "
            f"Shared input {point.input_power_dbm:g} dBm, backoff {point.backoff_db:g} dB, "
            f"architecture {point.architecture}. "
            "Switch the active canvas above to edit. Refresh comparison after changes. "
            "Empty or rejected canvases have no inferred numeric result."
        ),
        ui.div(*cards, class_="workspace-comparison-grid"),
    )
