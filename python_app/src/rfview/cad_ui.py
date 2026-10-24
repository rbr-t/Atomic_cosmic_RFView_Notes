"""Read-only visual summaries for standalone RF-CAD documents."""

from __future__ import annotations

import math

from shiny import ui

from rfview.domain.cad import CADComponent, CADDesign

MAX_CAD_PREVIEW_COMPONENTS = 250
MAX_CAD_PREVIEW_DIMENSION_MM = 1_000_000
_PORT_RADIUS_MM = 0.2


def _rect(x: float, y: float, width: float, height: float, class_name: str) -> ui.Tag:
    return ui.Tag(
        "rect",
        x=x,
        y=y,
        width=width,
        height=height,
        class_=f"cad-shape {class_name}",
    )


def _port(x: float, y: float) -> ui.Tag:
    return ui.Tag(
        "circle",
        cx=x,
        cy=y,
        r=_PORT_RADIUS_MM,
        class_="cad-port-marker",
    )


def _numeric_param(component: CADComponent, key: str) -> float:
    value = component.params.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"RF-CAD preview requires numeric {key} on {component.id}")
    if not math.isfinite(value) or value <= 0:
        raise ValueError(f"RF-CAD preview requires finite positive {key} on {component.id}")
    return float(value)


def _component_shapes(
    component: CADComponent,
) -> tuple[list[ui.Tag], tuple[float, float, float, float]] | None:
    params = component.params
    kind = component.type
    top = "cad-layer-metal-bottom" if component.layer == "metal_bot" else "cad-layer-metal-top"
    bottom = "cad-layer-metal-bottom"
    shapes: list[ui.Tag]

    if kind in ("microstrip", "ms", "open_stub", "short_stub"):
        width = _numeric_param(component, "W")
        length = _numeric_param(component, "L")
        shapes = [_rect(0, -width / 2, length, width, top)]
        min_y = -width / 2
        max_y = width / 2
        max_x = length
        if kind == "open_stub":
            shapes.append(
                ui.Tag(
                    "path",
                    d=f"M {length:g} {-width:g} V {width:g}",
                    class_="cad-shape cad-open-end",
                )
            )
            min_y, max_y = -width, width
        elif kind == "short_stub":
            shapes.append(_rect(length, -width, width * 0.4, width * 2, "cad-ground-end"))
            min_y, max_y = -width, width
            max_x += width * 0.4
        else:
            shapes.append(_port(0, 0))
            shapes.append(_port(length, 0))
            min_y = min(min_y, -_PORT_RADIUS_MM)
            max_y = max(max_y, _PORT_RADIUS_MM)
            return shapes, (-_PORT_RADIUS_MM, max_x + _PORT_RADIUS_MM, min_y, max_y)
        return shapes, (0, max_x, min_y, max_y)

    if kind == "bend90":
        width = _numeric_param(component, "W")
        length = _numeric_param(component, "L")
        arm = length - width / 2
        if arm <= 0:
            return None
        corner_x = length - width
        shapes = [
            _rect(0, -width / 2, arm, width, top),
            _rect(corner_x, -length + width / 2, width, arm, top),
            _rect(corner_x, -width / 2, width / 2, width / 2, top),
            _port(0, 0),
            _port(length - width / 2, -arm),
        ]
        if params.get("miter", True):
            shapes.append(
                ui.Tag(
                    "path",
                    d=(
                        f"M {corner_x + width * 0.35:g} {-width / 2:g} "
                        f"L {corner_x + width / 2:g} {-width / 2 + width * 0.35:g}"
                    ),
                    class_="cad-miter",
                )
            )
        return shapes, (
            -_PORT_RADIUS_MM,
            length + _PORT_RADIUS_MM,
            -length + width / 2 - _PORT_RADIUS_MM,
            width / 2 + _PORT_RADIUS_MM,
        )

    if kind == "tee":
        width = _numeric_param(component, "W")
        length = _numeric_param(component, "L")
        shapes = [
            _rect(0, -width / 2, length, width, top),
            _rect(length / 2 - width / 2, -width / 2 - length / 2, width, length / 2, top),
            _port(0, 0),
            _port(length, 0),
            _port(length / 2, -(width / 2 + length / 2)),
        ]
        return shapes, (
            -_PORT_RADIUS_MM,
            length + _PORT_RADIUS_MM,
            -width / 2 - length / 2 - _PORT_RADIUS_MM,
            width / 2 + _PORT_RADIUS_MM,
        )

    if kind == "coupled":
        width = _numeric_param(component, "W")
        length = _numeric_param(component, "L")
        gap = _numeric_param(component, "gap")
        top_y = -(gap / 2 + width)
        bottom_y = gap / 2
        shapes = [
            _rect(0, top_y, length, width, top),
            _rect(0, bottom_y, length, width, bottom),
            ui.Tag(
                "path",
                d=f"M -0.3 0 H {length + 0.3:g}",
                class_="cad-coupled-guide",
            ),
        ]
        for x in (0, length):
            shapes.append(_port(x, top_y + width / 2))
            shapes.append(_port(x, bottom_y + width / 2))
        return shapes, (
            -0.3 - _PORT_RADIUS_MM,
            length + 0.3 + _PORT_RADIUS_MM,
            top_y - _PORT_RADIUS_MM,
            bottom_y + width + _PORT_RADIUS_MM,
        )

    if kind == "via":
        drill = _numeric_param(component, "drill")
        pad = _numeric_param(component, "pad")
        pad_radius = pad / 2
        shapes = [
            ui.Tag("circle", cx=0, cy=0, r=pad_radius, class_="cad-via-pad"),
            ui.Tag("circle", cx=0, cy=0, r=pad_radius * 0.65, class_="cad-via-barrel"),
            ui.Tag("circle", cx=0, cy=0, r=drill / 2, class_="cad-via-drill"),
        ]
        extent = max(pad_radius, drill / 2)
        return shapes, (-extent, extent, -extent, extent)

    if kind == "port":
        width = _numeric_param(component, "W")
        shapes = [
            ui.Tag(
                "path",
                d=f"M 0 0 L 0.4 {-width / 2:g} L 0.4 {width / 2:g} Z",
                class_="cad-port-arrow",
            ),
            _rect(0.8, -width / 2, 0.5, width, top),
            _port(1.3, 0),
        ]
        return shapes, (
            -_PORT_RADIUS_MM,
            1.3 + _PORT_RADIUS_MM,
            -width / 2 - _PORT_RADIUS_MM,
            width / 2 + _PORT_RADIUS_MM,
        )

    raise ValueError(f"Unsupported RF-CAD preview component: {kind}")


def _transformed_bounds(
    bounds: tuple[float, ...], x: float, y: float, rotation: float
) -> tuple[float, float, float, float]:
    min_x, max_x, min_y, max_y = bounds
    angle = math.radians(rotation)
    cos_angle = math.cos(angle)
    sin_angle = math.sin(angle)
    transformed = [
        (
            x + local_x * cos_angle - local_y * sin_angle,
            -y - local_x * sin_angle - local_y * cos_angle,
        )
        for local_x in (min_x, max_x)
        for local_y in (min_y, max_y)
    ]
    return (
        min(point[0] for point in transformed),
        max(point[0] for point in transformed),
        min(point[1] for point in transformed),
        max(point[1] for point in transformed),
    )


def cad_layout_preview(design: CADDesign) -> ui.Tag:
    selected = design.components[:MAX_CAD_PREVIEW_COMPONENTS]
    renderable: list[tuple[CADComponent, list[ui.Tag], tuple[float, float, float, float]]] = []
    skipped_dimensions = 0
    skipped_geometry = 0
    for component in selected:
        rendered = _component_shapes(component)
        if rendered is None:
            skipped_geometry += 1
            continue
        shapes, local_bounds = rendered
        if max(abs(value) for value in local_bounds) > MAX_CAD_PREVIEW_DIMENSION_MM:
            skipped_dimensions += 1
            continue
        bounds = _transformed_bounds(local_bounds, component.x, component.y, component.rotation)
        if not all(math.isfinite(value) for value in bounds):
            skipped_dimensions += 1
            continue
        renderable.append((component, shapes, bounds))

    components = [item[0] for item in renderable]
    if not components:
        if not selected:
            return ui.p("This CAD document has no components to preview.")
        empty_content: list[ui.Tag] = [ui.p("No components fit the bounded CAD preview.")]
        if skipped_dimensions:
            empty_content.append(
                ui.p(
                    f"{skipped_dimensions} component(s) were omitted because a geometry "
                    f"dimension exceeds {MAX_CAD_PREVIEW_DIMENSION_MM:,} mm. "
                    "All remain in the JSON export."
                )
            )
        if skipped_geometry:
            empty_content.append(
                ui.p(
                    f"{skipped_geometry} component(s) with degenerate dimensions were "
                    "omitted from the preview. All remain in the JSON export."
                )
            )
        return ui.div(
            *empty_content,
            class_="cad-layout-preview",
            role="region",
            **{"aria-label": "RF-CAD geometry overview"},
        )

    min_x = min(item[2][0] for item in renderable)
    max_x = max(item[2][1] for item in renderable)
    min_y = min(item[2][2] for item in renderable)
    max_y = max(item[2][3] for item in renderable)
    span_x = max_x - min_x
    span_y = max_y - min_y
    margin = max(span_x, span_y, 20.0) * 0.08
    left = min_x - margin
    top = min_y - margin
    width = max(span_x + 2 * margin, 20.0)
    height = max(span_y + 2 * margin, 12.0)
    graphics: list[ui.Tag] = []

    for component, shapes, _bounds in renderable:
        angle = math.radians(component.rotation)
        a = math.cos(angle)
        b = -math.sin(angle)
        c = -math.sin(angle)
        d = -math.cos(angle)
        description = (
            f"{component.name or component.id}; {component.type}; layer={component.layer}; "
            f"x={component.x:g} mm, y={component.y:g} mm, "
            f"rotation={component.rotation:g} degrees"
        )
        if component.type == "port" and component.params.get("portNum") is not None:
            description += f"; port number {component.params['portNum']}"
        graphics.append(
            ui.Tag(
                "g",
                ui.tags.title(description),
                *shapes,
                class_="cad-layout-component",
                role="img",
                tabindex="0",
                transform=f"matrix({a:g} {b:g} {c:g} {d:g} {component.x:g} {-component.y:g})",
                **{"aria-label": description},
            )
        )

    preview = ui.tags.svg(
        ui.tags.title("Standalone RF-CAD component geometry overview"),
        *graphics,
        viewBox=f"{left:g} {top:g} {width:g} {height:g}",
        role="img",
        **{"aria-label": "RF-CAD component geometry in millimetres"},
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
    if skipped_dimensions:
        content.append(
            ui.p(
                f"{skipped_dimensions} component(s) were omitted from the preview because "
                f"a geometry dimension exceeds {MAX_CAD_PREVIEW_DIMENSION_MM:,} mm. "
                "All remain in the JSON export."
            )
        )
    if skipped_geometry:
        content.append(
            ui.p(
                f"{skipped_geometry} component(s) with degenerate dimensions were omitted "
                "from the preview. All remain in the JSON export."
            )
        )
    return ui.div(
        *content,
        class_="cad-layout-preview",
        role="region",
        **{"aria-label": "RF-CAD position overview"},
    )
