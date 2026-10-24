"""Read-only visual summaries for standalone RF-CAD documents."""

from __future__ import annotations

from shiny import ui

from rfview.domain.cad import CADDesign

MAX_CAD_PREVIEW_COMPONENTS = 250
_TYPE_LABELS = {
    "microstrip": "MS",
    "ms": "MS",
    "bend90": "B90",
    "tee": "TEE",
    "coupled": "CPL",
    "via": "VIA",
    "port": "P",
    "open_stub": "OS",
    "short_stub": "SS",
}


def cad_layout_preview(design: CADDesign) -> ui.Tag:
    components = design.components[:MAX_CAD_PREVIEW_COMPONENTS]
    if not components:
        return ui.p("This CAD document has no components to preview.")

    xs = [component.x for component in components]
    ys = [-component.y for component in components]
    span_x = max(xs) - min(xs)
    span_y = max(ys) - min(ys)
    margin = max(span_x, span_y, 20.0) * 0.08
    left = min(xs) - margin
    top = min(ys) - margin
    width = max(span_x + 2 * margin, 20.0)
    height = max(span_y + 2 * margin, 12.0)
    marker_radius = max(max(width, height) * 0.008, 0.1)
    markers: list[ui.Tag] = []

    for component in components:
        x = component.x
        y = -component.y
        description = (
            f"{component.name or component.id}; {component.type}; "
            f"x={component.x:g} mm, y={component.y:g} mm, "
            f"rotation={component.rotation:g} degrees"
        )
        markers.append(
            ui.Tag(
                "g",
                ui.tags.title(description),
                ui.Tag(
                    "circle",
                    cx=x,
                    cy=y,
                    r=marker_radius,
                    class_=f"cad-layout-marker cad-layout-{component.type}",
                ),
                class_="cad-layout-component",
                role="img",
                tabindex="0",
                **{"aria-label": description},
            )
        )

    preview = ui.tags.svg(
        ui.tags.title("Standalone RF-CAD component position overview"),
        *markers,
        viewBox=f"{left:g} {top:g} {width:g} {height:g}",
        role="img",
        **{"aria-label": "RF-CAD component positions in millimetres"},
        class_="cad-layout-svg",
    )
    content: list[ui.Tag] = [preview]
    if len(design.components) > MAX_CAD_PREVIEW_COMPONENTS:
        content.append(
            ui.p(
                f"Showing the first {MAX_CAD_PREVIEW_COMPONENTS} of "
                f"{len(design.components)} components; the complete document remains "
                "available in the JSON export."
            )
        )
    return ui.div(
        *content,
        class_="cad-layout-preview",
        role="region",
        **{"aria-label": "RF-CAD position overview"},
    )
