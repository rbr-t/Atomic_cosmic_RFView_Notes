import math

from shiny import ui

from rfview.domain.stability import StabilityCircle
from rfview.domain.touchstone import TouchstonePoint


def stability_circle_chart(circle: StabilityCircle | None, port: str, frequency: float) -> ui.Tag:
    if port not in ("Load", "Source"):
        raise ValueError("Circle port must be Load or Source")
    if circle is None:
        return ui.div(ui.h3(f"{port} circle"), ui.p("Undefined finite circle; see model warnings."))
    extent = max(1.0, abs(circle.center_r) + circle.radius, abs(circle.center_i) + circle.radius)
    if not math.isfinite(extent):
        raise ValueError("Circle display extent exceeds numeric range")
    x = 300 + 240 * (circle.center_r / extent)
    y = 290 - 240 * (circle.center_i / extent)
    radius = 240 * (circle.radius / extent)
    return ui.tags.figure(
        ui.tags.figcaption(f"{port} stability circle at {frequency:g} GHz"),
        ui.HTML(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600" '
            f'role="img" aria-label="{port} stability circle">'
            f"<title>{port} reflection-coefficient boundary</title>"
            "<desc>Full circle in the complex Gamma plane, not a Smith impedance grid. "
            "Positive imaginary values point upward. No stable side is inferred.</desc>"
            '<path class="chart-axis" d="M60 290H540M300 50V530"/>'
            f'<circle class="chart-grid passive-boundary" cx="300" cy="290" '
            f'r="{240 / extent:.12g}" fill="none"/>'
            f'<circle class="smith-trace stability-circle" cx="{x:.12g}" cy="{y:.12g}" '
            f'r="{radius:.12g}" fill="none"/>'
            f'<circle class="smith-point" cx="{x:.12g}" cy="{y:.12g}" r="3"/>'
            '<text x="300" y="555" text-anchor="middle">Real Gamma (horizontal)</text>'
            f'<text x="300" y="585" text-anchor="middle">Axis limits: +/-{extent:.6g}</text>'
            "</svg>"
        ),
        ui.p(
            f"Center: {circle.center_r:.12g}{circle.center_i:+.12g}j | "
            f"Radius: {circle.radius:.12g} (dimensionless). "
            "Dashed circle: |Gamma| = 1. Each plot is scaled independently to show "
            "the entire boundary, including regions outside the passive unit disk. "
            "The center marker is not a stable-side indicator."
        ),
        class_="technology-chart smith-chart",
    )


def smith_chart(points: list[TouchstonePoint], parameter: str, z0: float) -> ui.Tag:
    if not (
        len(parameter) == 3
        and parameter.startswith("S")
        and parameter[1] == parameter[2]
        and parameter[1] in "123456789"
    ):
        raise ValueError(
            "Smith view requires S11 or S22 (or another diagonal reflection), not transmission data"
        )
    for point in points:
        if math.hypot(point.real, point.imag) > 1 + 1e-12:
            raise ValueError(
                f"Smith view cannot display |{parameter}| > 1 at {point.freq_ghz:g} GHz. "
                "No partial trace is displayed; select S to inspect the source data."
            )
    grid = []
    for resistance in (0.2, 0.5, 1, 2, 5):
        grid.append(
            f'<circle class="chart-grid" cx="{300 + 240 * resistance / (1 + resistance):.6f}" '
            f'cy="290" r="{240 / (1 + resistance):.6f}" fill="none"/>'
        )
    # Map constant-reactance loci through Gamma=(z-1)/(z+1).
    for reactance in (-5, -2, -1, -0.5, -0.2, 0.2, 0.5, 1, 2, 5):
        coordinates = []
        for index in range(161):
            resistance = 10 ** (-4 + index * 8 / 160) if index else 0
            z = complex(resistance, reactance)
            gamma = (z - 1) / (z + 1)
            coordinates.append(f"{300 + 240 * gamma.real:.6f},{290 - 240 * gamma.imag:.6f}")
        grid.append(f'<polyline class="chart-grid" fill="none" points="{" ".join(coordinates)}"/>')
    trace = " ".join(f"{300 + 240 * p.real:.6f},{290 - 240 * p.imag:.6f}" for p in points)
    markers = "".join(
        f'<circle class="smith-point" cx="{300 + 240 * p.real:.6f}" '
        f'cy="{290 - 240 * p.imag:.6f}" r="3">'
        f"<title>{parameter}: {p.freq_ghz:g} GHz; "
        f"Gamma={p.real:.6g}{p.imag:+.6g}j</title></circle>"
        for p in points
    )
    return ui.tags.figure(
        ui.tags.figcaption(f"{parameter} impedance Smith chart"),
        ui.HTML(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600" '
            f'role="img" aria-label="{parameter} impedance Smith chart">'
            f"<title>{parameter} reflection coefficient</title>"
            "<desc>Impedance Smith grid normalized to the uploaded reference impedance. "
            "Center is matched, left is short, right is open. "
            "Positive reactance is above the real axis. Points follow increasing frequency.</desc>"
            '<circle class="chart-axis" cx="300" cy="290" r="240"/>'
            '<path class="chart-axis" d="M60 290H540"/>'
            + "".join(grid)
            + f'<polyline class="smith-trace" fill="none" points="{trace}"/>'
            + markers
            + '<text x="300" y="275" text-anchor="middle">Matched</text>'
            '<text x="60" y="555" text-anchor="middle">Short</text>'
            '<text x="540" y="555" text-anchor="middle">Open</text>'
            f'<text x="300" y="585" text-anchor="middle">Reference: {z0:g} ohm</text>'
            "</svg>"
        ),
        ui.p(
            "Impedance grid: normalized resistance r = 0.2, 0.5, 1, 2, 5; "
            "normalized reactance x = +/-0.2, 0.5, 1, 2, 5. "
            "Trace markers follow increasing frequency; hover for frequency and Gamma. "
            "The unit circle is a display boundary, not a network passivity certification."
        ),
        class_="technology-chart smith-chart",
    )
