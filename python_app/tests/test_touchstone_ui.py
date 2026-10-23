import re
from pathlib import Path
from xml.etree import ElementTree

import pytest

from rfview.domain.touchstone import parse_touchstone
from rfview.services import read_touchstone
from rfview.touchstone_ui import touchstone_panel

NS = {"s": "http://www.w3.org/2000/svg"}
FIXTURE = Path(__file__).parent / "fixtures" / "touchstone" / "reference_db.s2p"


def test_negative_magnitude_phase_fit_chart_bounds() -> None:
    network = read_touchstone(FIXTURE)
    html = str(touchstone_panel(network, "S21"))
    svgs = [ElementTree.fromstring(s) for s in re.findall(r"<svg.*?</svg>", html, re.S)]
    assert len(svgs) == 2
    for svg in svgs:
        line = svg.find("s:polyline", NS)
        assert line is not None
        coords = [tuple(map(float, pair.split(","))) for pair in line.attrib["points"].split()]
        assert len(coords) == 2
        assert all(75 <= x <= 725 and 40 <= y <= 290 for x, y in coords)
    phase_labels = [t.text for t in svgs[1].findall("s:text", NS)]
    assert any(label and label.startswith("-") for label in phase_labels)
    assert "Reference impedance: 50 ohm" in html
    assert "S21 magnitude" in html


def test_single_record_is_visible_and_filename_escaped() -> None:
    network = parse_touchstone("1 0.1 -90", "<script>.s1p")
    html = str(touchstone_panel(network, "S11"))
    assert html.count("<circle") == 2
    assert "<script>" not in html
    with pytest.raises(ValueError, match="not present"):
        touchstone_panel(network, "S21")


def test_upload_filename_independent_of_temp_path(tmp_path: Path) -> None:
    path = tmp_path / "random-upload"
    path.write_text("# GHz S RI R 50\n1 0.1 0", encoding="utf-8")
    assert read_touchstone(path, filename="original.s1p").filename == "original.s1p"


def test_viewer_record_limit_is_explicit() -> None:
    network = parse_touchstone("\n".join(f"{i} 0.1 0" for i in range(2001)), "large.s1p")
    with pytest.raises(ValueError, match="2000"):
        touchstone_panel(network, "S11")


@pytest.mark.parametrize("representation,unit", [("Z", "ohm"), ("Y", "S")])
def test_conversion_plot_coordinates_and_units(representation: str, unit: str) -> None:
    from rfview.domain.network_parameters import s_to_y, s_to_z

    network = read_touchstone(FIXTURE)
    html = str(touchstone_panel(network, "S21", representation))
    assert f"{representation}21 real" in html
    assert f"Imaginary ({unit})" in html
    record = {p.param: complex(p.real, p.imag) for p in network.points[:4]}
    matrix = ((record["S11"], record["S12"]), (record["S21"], record["S22"]))
    value = (s_to_z if representation == "Z" else s_to_y)(matrix, network.z0)[1][0]
    svgs = [ElementTree.fromstring(s) for s in re.findall(r"<svg.*?</svg>", html, re.S)]
    for svg, component in zip(svgs, (value.real, value.imag), strict=True):
        line = svg.find("s:polyline", NS)
        assert line is not None
        x, y = map(float, line.attrib["points"].split()[0].split(","))
        assert x == 75
        assert 40 <= y <= 290
        assert component != 0
    expected_values = []
    for index in range(len(network.freq_ghz)):
        record = {
            p.param: complex(p.real, p.imag) for p in network.points[index * 4 : index * 4 + 4]
        }
        matrix = ((record["S11"], record["S12"]), (record["S21"], record["S22"]))
        expected_values.append(
            (s_to_z if representation == "Z" else s_to_y)(matrix, network.z0)[1][0]
        )
    for svg, component_name in zip(svgs, ("real", "imag"), strict=True):
        values = [getattr(value, component_name) for value in expected_values]
        low, high = min(min(values) * 1.08, 0), max(max(values) * 1.08, 1)
        line = svg.find("s:polyline", NS)
        assert line is not None
        coordinates = [tuple(map(float, p.split(","))) for p in line.attrib["points"].split()]
        for (_, y), value in zip(coordinates, values, strict=True):
            assert y == pytest.approx(290 - (value - low) / (high - low) * 250, abs=0.00051)


@pytest.mark.parametrize("representation,diagonal", [("Z", 1), ("Y", -1)])
def test_singular_frequency_is_reported_without_partial_curve(
    representation: str, diagonal: int
) -> None:
    network = parse_touchstone(
        f"# GHz S RI R 50\n1 0 0 0 0 0 0 0 0\n2 {diagonal} 0 0 0 0 0 0 0",
        "singular.s2p",
    )
    with pytest.raises(ValueError, match="failed at 2 GHz"):
        touchstone_panel(network, "S21", representation)
    assert "S21 magnitude" in str(touchstone_panel(network, "S21"))


@pytest.mark.parametrize("representation", ["Z", "Y", "invalid"])
def test_unsupported_views_fail_explicitly(representation: str) -> None:
    network = parse_touchstone("1 0.1 0", "one.s1p")
    with pytest.raises(ValueError):
        touchstone_panel(network, "S11", representation)


def test_stability_table_uses_complete_network_and_qualified_metrics() -> None:
    from rfview.domain.stability import stability_metrics

    network = read_touchstone(FIXTURE)
    before = network.model_dump()
    html = str(touchstone_panel(network, "S21", "Stability"))
    assert html == str(touchstone_panel(network, "S12", "Stability"))
    table = ElementTree.fromstring(re.search(r"<table.*?</table>", html, re.S)[0])
    rows = table.findall("tbody/tr")
    assert len(rows) == len(network.freq_ghz)
    for index, row in enumerate(rows):
        record = {
            p.param: complex(p.real, p.imag) for p in network.points[index * 4 : index * 4 + 4]
        }
        metrics = stability_metrics(
            ((record["S11"], record["S12"]), (record["S21"], record["S22"]))
        )
        assert float(row.find("th").text) == network.freq_ghz[index]
        expected = [
            metrics.delta_mag,
            metrics.K,
            metrics.mu_in,
            metrics.mu_out,
            metrics.B1,
            metrics.msg_db,
            metrics.mag_db,
        ]
        cells = row.findall("td")
        for cell, value in zip(cells[:7], expected, strict=True):
            if value is None:
                assert cell.text == "Undefined"
            else:
                assert float(cell.text) == pytest.approx(value, rel=1e-10, abs=1e-12)
        assert cells[7].text == str(metrics.stable)
    assert "20*log10" in html and "not the conventional 10*log10" in html
    assert "not a full stability certification" in html
    assert "legacy-r-stability-v1" in html
    assert 'tabindex="0"' in html
    assert network.model_dump() == before


def test_stability_undefined_values_are_not_silently_omitted() -> None:
    network = parse_touchstone("# GHz S RI R 50\n1 0 0 0 0 0 0 0 0", "matched.s2p")
    html = str(touchstone_panel(network, "S11", "Stability"))
    assert html.count("<tr>") == 2
    assert html.count("<td>Undefined</td>") == 5
    assert "<td>False</td>" in html
    assert "legacy infinite-K case" in html
    assert "mu denominator is negligible" in html


def test_stability_rejects_one_port_and_reports_numeric_failure_frequency() -> None:
    one_port = parse_touchstone("1 0.1 0", "one.s1p")
    with pytest.raises(ValueError, match="requires a two-port dataset"):
        touchstone_panel(one_port, "S11", "Stability")
    network = parse_touchstone(
        "# GHz S RI R 50\n1 0 0 0 0 0 0 0 0\n2 1e200 0 0 0 0 0 0 0", "overflow.s2p"
    )
    with pytest.raises(ValueError, match="failed at 2 GHz.*No partial table"):
        touchstone_panel(network, "S11", "Stability")
    assert "S11 magnitude" in str(touchstone_panel(network, "S11"))


def test_circle_view_frequency_selection_geometry_and_undefined_cases() -> None:
    network = parse_touchstone(
        "# GHz S RI R 50\n1 0 0 2 0 0.1 0 0 0\n2 0 0 0 0 0 0 0 0", "circles.s2p"
    )
    html = str(touchstone_panel(network, "S21", "Circles", 0))
    assert html == str(touchstone_panel(network, "S12", "Circles", 0))
    svgs = [ElementTree.fromstring(s) for s in re.findall(r"<svg.*?</svg>", html, re.S)]
    assert len(svgs) == 2
    for svg in svgs:
        circle = svg.find("s:circle[@class='smith-trace stability-circle']", NS)
        assert float(circle.attrib["r"]) == pytest.approx(240)
        assert float(circle.attrib["cx"]) == pytest.approx(300)
        assert float(circle.attrib["cy"]) == pytest.approx(290)
        passive = svg.find("s:circle[@class='chart-grid passive-boundary']", NS)
        assert float(passive.attrib["r"]) == pytest.approx(48)
    assert "Axis limits: +/-5" in html
    assert "No stable side is inferred" in html
    undefined = str(touchstone_panel(network, "S11", "Circles", 1))
    assert "Undefined finite circle" in undefined
    assert "<svg" not in undefined
    with pytest.raises(ValueError, match="available circle frequency"):
        touchstone_panel(network, "S11", "Circles", 2)
    with pytest.raises(ValueError, match="two-port"):
        touchstone_panel(parse_touchstone("1 0 0", "one.s1p"), "S11", "Circles")


def test_circle_view_asymmetric_center_orientation_matches_metrics() -> None:
    from rfview.domain.stability import stability_circles
    from rfview.smith_ui import stability_circle_chart

    circles = stability_circles(((0.1 + 0.2j, 0.3 + 0.4j), (2 - 0.5j, -0.2 + 0.1j)))
    for port, circle in (("Load", circles.load), ("Source", circles.source)):
        assert circle is not None
        html = str(stability_circle_chart(circle, port, 2))
        svg = ElementTree.fromstring(re.search(r"<svg.*?</svg>", html, re.S)[0])
        shape = svg.find("s:circle[@class='smith-trace stability-circle']", NS)
        extent = max(1, abs(circle.center_r) + circle.radius, abs(circle.center_i) + circle.radius)
        assert float(shape.attrib["cx"]) == pytest.approx(300 + 240 * circle.center_r / extent)
        assert float(shape.attrib["cy"]) == pytest.approx(290 - 240 * circle.center_i / extent)
        assert float(shape.attrib["r"]) == pytest.approx(240 * circle.radius / extent)


@pytest.mark.parametrize(
    "representation,param,label,unit",
    [
        ("h", "S11", "h11", "ohm"),
        ("h", "S22", "h22", "S"),
        ("h", "S21", "h21", "dimensionless"),
        ("ABCD", "S11", "A", "dimensionless"),
        ("ABCD", "S12", "B", "ohm"),
        ("ABCD", "S21", "C", "S"),
        ("ABCD", "S22", "D", "dimensionless"),
        ("T", "S21", "T21", "dimensionless"),
    ],
)
def test_transfer_view_labels_and_units(
    representation: str, param: str, label: str, unit: str
) -> None:
    html = str(touchstone_panel(read_touchstone(FIXTURE), param, representation))
    assert f"{label} real" in html
    assert f"Imaginary ({unit})" in html
    assert html.count("<svg") == 2


@pytest.mark.parametrize("representation", ["h", "ABCD", "T"])
def test_transfer_singular_frequency_and_one_port_rejection(representation: str) -> None:
    diagonal = -1 if representation == "h" else 0
    network = parse_touchstone(
        f"# GHz S RI R 50\n1 0.1 0 2 0 0.1 0 0.2 0\n2 0 0 0 0 0 0 {diagonal} 0", "singular.s2p"
    )
    with pytest.raises(ValueError, match="failed at 2 GHz"):
        touchstone_panel(network, "S11", representation)
    with pytest.raises(ValueError, match="two-port"):
        touchstone_panel(parse_touchstone("1 0 0", "one.s1p"), "S11", representation)
