from html import escape

from shiny import ui

from rfview.domain.loadpull import LoadPullData, LoadPullPoint
from rfview.domain.loadpull_contours import (
    METRICS,
    LoadPullMetric,
    SweepKey,
    loadpull_contours,
    loadpull_sweeps,
)
from rfview.technology_ui import Trace, line_chart

MAX_LOADPULL_VIEW_POINTS = 2000


def cst_wave_panel(data: LoadPullData) -> ui.Tag:
    if data.format != "cst":
        return ui.div()
    if len(data.points) > MAX_LOADPULL_VIEW_POINTS:
        raise ValueError("CST wave view exceeds 2000 points; select a smaller block")
    fields = {
        "frequency_hz": "Frequency (Hz)",
        "v1_v": "V1 (V)",
        "i1_a": "I1 (A)",
        "v2_v": "V2 (V)",
        "i2_a": "I2 (A)",
        **{
            f"{wave}_{part}": f"{wave} {part} (declared wave units)"
            for wave in ("a1", "b1", "a2", "b2")
            for part in ("real", "imag")
        },
        "z0source": "Source Z0 (ohm)",
        "z0load": "Load Z0 (ohm)",
    }
    traces = []
    for key, label, color in (
        ("pin_w", "Net input (W)", "#56B4E9"),
        ("pout_w", "Net output (W)", "#E69F00"),
    ):
        values = []
        for i, point in enumerate(data.points, 1):
            value = getattr(point, key)
            if value is None:
                raise ValueError("CST net wave power is undefined; no partial sweep is drawn")
            values.append((float(i), value))
        traces.append(Trace(label, values, color))
    return ui.div(
        ui.h4("CST block net-power sweep and raw waves"),
        ui.p(
            f"Declared normalization: {data.metadata['wave_normalization']}. "
            "Whole imported block in source row order, independent of the exact "
            "Gamma/Pin/bias grouping above. No interpolation or harmonic summation. "
            "Raw waves retain declared units: peak V, RMS V, or sqrt(W)."
        ),
        line_chart("CST net wave powers", "Source block row (index)", "Net power (W)", traces),
        ui.div(
            ui.tags.table(
                ui.tags.caption("CST raw source waves, DC and port references"),
                ui.tags.thead(
                    ui.tags.tr(
                        ui.tags.th("Row", scope="col"),
                        *(ui.tags.th(label, scope="col") for label in fields.values()),
                    )
                ),
                ui.tags.tbody(
                    *(
                        ui.tags.tr(
                            ui.tags.th(str(index), scope="row"),
                            *(
                                ui.tags.td(
                                    "Undefined"
                                    if point.extra.get(f"source.{key}") is None
                                    else f"{point.extra[f'source.{key}']:.12g}"
                                )
                                for key in fields
                            ),
                        )
                        for index, point in enumerate(data.points, 1)
                    )
                ),
                id="cst_wave_table",
            ),
            class_="table-scroll",
            tabindex="0",
            role="region",
            **{"aria-label": "Scrollable CST raw source waves"},
        ),
    )


def _backoff(data: LoadPullData) -> float | None:
    if data.format == "alps_mdf" and data.metadata.get("selection_kind") == "backoff":
        return float(data.metadata["backoff_db"])
    return None


def _viewer_sweeps(data: LoadPullData) -> dict[SweepKey, tuple[LoadPullPoint, ...]]:
    if _backoff(data) is None:
        return loadpull_sweeps(data.points)
    grouped: dict[SweepKey, list[LoadPullPoint]] = {}
    for point in data.points:
        grouped.setdefault((point.freq_ghz, None, None, None, None), []).append(point)
    return {key: tuple(points) for key, points in grouped.items()}


def sweep_choices(data: LoadPullData) -> dict[str, str]:
    def label(value: float | None) -> str:
        return "unknown" if value is None else f"{value:.12g}"

    return {
        f"sweep-{i}": (
            f"{label(key[0])} GHz | source BO {_backoff(data):.12g} dB | "
            "Pin/source Gamma/bias may vary (not a fixed-Pin sweep)"
            if _backoff(data) is not None
            else f"{label(key[0])} GHz | Pin {label(key[1])} dBm | "
            f"Gs {label(key[2])},{label(key[3])} | Vdc {label(key[4])} V"
        )
        for i, key in enumerate(_viewer_sweeps(data))
    }


def loadpull_panel(
    data: LoadPullData, sweep: str, metric: LoadPullMetric, contours: bool = False
) -> ui.Tag:
    if len(data.points) > MAX_LOADPULL_VIEW_POINTS:
        raise ValueError(
            f"Viewer limit is {MAX_LOADPULL_VIEW_POINTS} load-pull points; no decimation"
        )
    if metric not in METRICS:
        raise ValueError("Choose a supported load-pull metric")
    groups = list(_viewer_sweeps(data).values())
    choices = sweep_choices(data)
    if sweep not in choices:
        raise ValueError("Choose an available load-pull sweep")
    points = groups[list(choices).index(sweep)]
    label, unit = METRICS[metric]
    measured = [getattr(p, metric) for p in points]
    levels: tuple[float, ...] = ()
    if contours:
        if len(points) < 3:
            raise ValueError("Contours require 3-2000 measurement points in the selected sweep")
        if any(value is None for value in measured):
            raise ValueError("Contour metric is undefined; choose the measured-point view")
        numeric: list[float] = [value for value in measured if value is not None]
        low, high = min(numeric), max(numeric)
        if high == low:
            raise ValueError("Constant metric: no distinct contour levels; choose measured points")
        levels = tuple(low * (1 - i / 6) + high * (i / 6) for i in range(1, 6))
    segments = (
        loadpull_contours(points, metric, levels, backoff_db=_backoff(data)) if contours else ()
    )
    extent = max(1, *(max(abs(p.gl_r), abs(p.gl_i)) for p in points))

    def x(value: float) -> float:
        return 300 + 240 * (value / extent)

    def y(value: float) -> float:
        return 290 - 240 * (value / extent)

    svg = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600" '
        'role="img" aria-label="Load-pull measured Gamma and contours">',
        "<title>Load-pull complex reflection plane</title>"
        "<desc>Measured load Gamma points. Positive imaginary values upward. "
        "Contour segments, when selected, use linear interpolation "
        "within measured triangles only.</desc>",
        '<path class="chart-axis" d="M60 290H540M300 50V530"/>',
        f'<circle class="chart-grid" cx="300" cy="290" r="{240 / extent:.12g}" fill="none"/>',
    ]
    for segment in segments:
        svg.append(
            f'<path class="smith-trace loadpull-contour" fill="none" '
            f'd="M{x(segment.start[0]):.12g} {y(segment.start[1]):.12g}'
            f'L{x(segment.end[0]):.12g} {y(segment.end[1]):.12g}">'
            f"<title>{segment.level:.12g} {escape(unit)}</title></path>"
        )
    for index, (point, value) in enumerate(zip(points, measured, strict=True), 1):
        text = "Undefined" if value is None else f"{value:.12g} {unit}"
        svg.append(
            f'<circle class="smith-point loadpull-point" cx="{x(point.gl_r):.12g}" '
            f'cy="{y(point.gl_i):.12g}" r="3"><title>'
            f"Point {index}: Gamma={point.gl_r:.12g}{point.gl_i:+.12g}j; "
            f"{escape(label)}: {escape(text)}</title></circle>"
        )
    svg.append(
        '<text x="300" y="555" text-anchor="middle">Real Gamma (horizontal)</text>'
        f'<text x="300" y="585" text-anchor="middle">Axis limits: +/-{extent:.6g}</text></svg>'
    )
    return ui.div(
        ui.h3(f"{label} ({unit}) - {data.filename}"),
        ui.p(
            f"Adapter: {data.format} | {len(points)} selected / "
            f"{len(data.points)} total measurements"
        ),
        ui.p(choices[sweep]),
        ui.tags.ul(*(ui.tags.li(warning) for warning in data.warnings)),
        ui.tags.figure(
            ui.tags.figcaption("Load-pull measured points / contours"),
            ui.HTML("".join(svg)),
            class_="technology-chart smith-chart",
        ),
        ui.p(
            "Contours are piecewise-linear Delaunay estimates inside the measured convex hull; "
            "no extrapolation or smoothing. Triangles can span unmeasured gaps. "
            "No calibration, optimum-load or device-safety certification. "
            "Duplicate coordinates or undefined metrics reject contours "
            "rather than average/drop data."
        ),
        ui.p("Contour levels: " + (", ".join(f"{v:.6g} {unit}" for v in levels) or "off")),
        cst_wave_panel(data),
        ui.div(
            ui.tags.table(
                ui.tags.caption("Selected load-pull measurements (not interpolated)"),
                ui.tags.thead(
                    ui.tags.tr(
                        *(
                            ui.tags.th(v, scope="col")
                            for v in (
                                "Point",
                                "Gamma real",
                                "Gamma imaginary",
                                f"{label} ({unit})",
                            )
                        )
                    )
                ),
                ui.tags.tbody(
                    *(
                        ui.tags.tr(
                            ui.tags.th(str(i), scope="row"),
                            ui.tags.td(f"{p.gl_r:.12g}"),
                            ui.tags.td(f"{p.gl_i:.12g}"),
                            ui.tags.td("Undefined" if v is None else f"{v:.12g}"),
                        )
                        for i, (p, v) in enumerate(zip(points, measured, strict=True), 1)
                    )
                ),
                id="loadpull_measurement_table",
            ),
            class_="table-scroll",
            tabindex="0",
            role="region",
            **{"aria-label": "Scrollable selected load-pull measurements"},
        ),
    )
