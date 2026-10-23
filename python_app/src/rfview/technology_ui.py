from __future__ import annotations

import math
from dataclasses import dataclass
from html import escape

from shiny import ui

from rfview.domain.guardrails import (
    GuardrailCatalog,
    build_design_space_data,
    build_gain_bandwidth_data,
    build_guardrail_summary_table,
    build_pae_backoff_data,
)


@dataclass(frozen=True)
class Trace:
    label: str
    points: list[tuple[float, float]]
    color: str
    dashed: bool = False


def _chart(
    title: str,
    x_label: str,
    y_label: str,
    traces: list[Trace],
    *,
    log_x: bool = False,
) -> ui.Tag:
    points = [point for trace in traces for point in trace.points]
    if not points:
        return ui.p(f"No data available for {title}.")
    xs = [math.log10(x) if log_x else x for x, _ in points]
    ys = [y for _, y in points]
    xmin, xmax = min(xs), max(xs)
    ymin, ymax = 0.0, max(max(ys) * 1.08, 1)
    if xmax == xmin:
        xmax = xmin + 1

    def px(x: float) -> float:
        return 75 + ((math.log10(x) if log_x else x) - xmin) / (xmax - xmin) * 650

    def py(y: float) -> float:
        return 290 - (y - ymin) / (ymax - ymin) * 250

    svg = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 360" '
        f'role="img" aria-label="{escape(title, quote=True)}">',
        f"<title>{escape(title)}</title>",
        f"<desc>{escape(x_label)} versus {escape(y_label)}. "
        "Each trace is labelled in the legend. Dashed lines denote maximum gain. "
        "Choose one technology to inspect its curves without overlap.</desc>",
        '<path class="chart-axis" d="M75 40V290H725"/>',
    ]
    for index in range(6):
        xv = xmin + (xmax - xmin) * index / 5
        x, y = 75 + 650 * index / 5, 290 - 250 * index / 5
        xvalue = 10**xv if log_x else xv
        yvalue = ymax * index / 5
        svg.extend(
            [
                f'<path class="chart-grid" d="M75 {y:.3f}H725"/>',
                f'<text x="{x:.3f}" y="312" text-anchor="middle">{xvalue:.3g}</text>',
                f'<text x="65" y="{y + 4:.3f}" text-anchor="end">{yvalue:.3g}</text>',
            ]
        )
    for trace in traces:
        coordinates = " ".join(f"{px(x):.3f},{py(y):.3f}" for x, y in trace.points)
        svg.append(
            f'<polyline class="chart-trace" style="--trace-color:{escape(trace.color)}" '
            f'points="{coordinates}" fill="none" stroke-width="2" '
            f'stroke-dasharray="{"7 4" if trace.dashed else "none"}">'
            f"<title>{escape(trace.label)}</title></polyline>"
        )
    svg.extend(
        [
            f'<text x="400" y="345" text-anchor="middle">{escape(x_label)}</text>',
            f'<text transform="translate(18 165) rotate(-90)" text-anchor="middle">'
            f"{escape(y_label)}</text>",
            "</svg>",
        ]
    )
    return ui.tags.figure(
        ui.tags.figcaption(title),
        ui.HTML("".join(svg)),
        ui.tags.ul(
            *(
                ui.tags.li(
                    ui.tags.span(
                        " ",
                        class_="legend-swatch dashed" if trace.dashed else "legend-swatch",
                        style=f"--trace-color:{trace.color}",
                        **{"aria-hidden": "true"},
                    ),
                    trace.label,
                )
                for trace in traces
            ),
            class_="chart-legend",
        ),
        class_="technology-chart",
    )


def technology_panel(catalog: GuardrailCatalog, technology: str, pa_class: str) -> ui.Tag:
    if technology != "all" and technology not in catalog.technologies:
        raise ValueError(f"Unknown chart technology: {technology}")
    if pa_class not in ("A", "AB", "B", "Doherty", "F"):
        raise ValueError(f"Unsupported chart PA class: {pa_class}")
    selected = catalog.model_copy(
        update={
            "technologies": {
                key: tech
                for key, tech in catalog.technologies.items()
                if technology == "all" or key == technology
            }
        }
    )
    design = build_design_space_data(selected)
    gains = build_gain_bandwidth_data(selected)
    backoff = build_pae_backoff_data(selected)
    density_traces, gain_traces, pae_traces = [], [], []
    for key, tech in selected.technologies.items():
        density_traces.append(
            Trace(
                tech.label,
                [
                    (row["freq_ghz"], row["pout_density_typ"])
                    for row in design
                    if row["tech"] == key
                ],
                tech.color,
            )
        )
        for field, label, dashed in (("gain_typ", "typical", False), ("gain_max", "maximum", True)):
            gain_traces.append(
                Trace(
                    f"{tech.label} - {label}",
                    [
                        (
                            row["freq_ghz"],
                            row["gain_typ"] if field == "gain_typ" else row["gain_max"],
                        )
                        for row in gains
                        if row["tech"] == key
                    ],
                    tech.color,
                    dashed,
                )
            )
        pae_traces.append(
            Trace(
                f"{tech.label} - {pa_class}",
                [
                    (row["backoff_db"], row["pae_pct"])
                    for row in backoff
                    if row["tech"] == key and row["pa_class"] == pa_class
                ],
                tech.color,
            )
        )
    summary = [dict(row) for row in build_guardrail_summary_table(selected)]
    columns = list(summary[0])
    return ui.div(
        ui.p(
            "Legacy empirical envelopes, not measured device data or safety limits. "
            "Frequency axes are logarithmic; power-density lines show typical values. "
            "Technology filters do not change the lineup or advisory."
        ),
        _chart(
            "Technology design space",
            "Frequency (GHz, log scale)",
            "Typical power density (W/mm)",
            density_traces,
            log_x=True,
        ),
        _chart(
            "Gain-bandwidth envelope",
            "Frequency (GHz, log scale)",
            "Available gain (dB)",
            gain_traces,
            log_x=True,
        ),
        _chart(f"PAE-backoff curves - {pa_class}", "Output backoff (dB)", "PAE (%)", pae_traces),
        ui.div(
            ui.tags.table(
                ui.tags.caption("Technology guardrail summary"),
                ui.tags.thead(ui.tags.tr(*(ui.tags.th(col, scope="col") for col in columns))),
                ui.tags.tbody(
                    *(
                        ui.tags.tr(
                            *(
                                ui.tags.td("-" if row[col] is None else str(row[col]))
                                for col in columns
                            )
                        )
                        for row in summary
                    )
                ),
                id="technology_summary_table",
            ),
            class_="table-scroll",
            tabindex="0",
            role="region",
            **{"aria-label": "Scrollable technology guardrail summary"},
        ),
    )
