import math

from shiny import ui

from rfview.domain.touchstone import TouchstonePoint


def smith_chart(points: list[TouchstonePoint], parameter: str, z0: float) -> ui.Tag:
    if parameter not in ("S11", "S22"):
        raise ValueError("Smith view requires S11 or S22 reflection data, not transmission data")
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
