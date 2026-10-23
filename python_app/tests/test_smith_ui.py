import re
from xml.etree import ElementTree

import pytest

from rfview.domain.touchstone import parse_touchstone
from rfview.touchstone_ui import touchstone_panel

NS = {"s": "http://www.w3.org/2000/svg"}


def test_short_match_open_and_reactance_orientation() -> None:
    network = parse_touchstone(
        "# GHz S RI R 75\n1 -1 0\n2 0 0\n3 1 0\n4 0 1\n5 0 -1", "geometry.s1p"
    )
    html = str(touchstone_panel(network, "S11", "Smith"))
    svg = ElementTree.fromstring(re.search(r"<svg.*?</svg>", html, re.S)[0])
    trace = svg.find("s:polyline[@class='smith-trace']", NS)
    assert trace is not None
    points = [tuple(map(float, p.split(","))) for p in trace.attrib["points"].split()]
    assert points == [(60, 290), (300, 290), (540, 290), (300, 50), (300, 530)]
    assert len(svg.findall("s:circle[@class='smith-point']", NS)) == 5
    assert "Reference: 75 ohm" in html
    assert "5 GHz" in html
    circles = svg.findall("s:circle[@class='chart-grid']", NS)
    assert len(circles) == 5
    unit_resistance = circles[2]
    assert float(unit_resistance.attrib["cx"]) == 420
    assert float(unit_resistance.attrib["r"]) == 120
    arcs = svg.findall("s:polyline[@class='chart-grid']", NS)
    assert len(arcs) == 10
    # x=-5 starts on the capacitive (lower) unit-circle boundary.
    first = tuple(map(float, arcs[0].attrib["points"].split()[0].split(",")))
    gamma = (complex(0, -5) - 1) / (complex(0, -5) + 1)
    assert first == pytest.approx((300 + 240 * gamma.real, 290 - 240 * gamma.imag), abs=1e-6)
    for arc in arcs:
        for pair in arc.attrib["points"].split():
            x, y = map(float, pair.split(","))
            assert (x - 300) ** 2 + (y - 290) ** 2 <= 240**2 + 0.001


@pytest.mark.parametrize("value", ["1.01 0", "0 -1.01"])
def test_active_reflection_is_not_clipped(value: str) -> None:
    network = parse_touchstone(f"# GHz S RI R 50\n1 0 0\n2 {value}", "active.s1p")
    with pytest.raises(ValueError, match="at 2 GHz"):
        touchstone_panel(network, "S11", "Smith")
    assert "S11 magnitude" in str(touchstone_panel(network, "S11"))


def test_transmission_is_not_treated_as_reflection() -> None:
    network = parse_touchstone("# GHz S RI R 50\n1 0 0 0.5 0 0.1 0 0 0", "two.s2p")
    with pytest.raises(ValueError, match="requires S11 or S22"):
        touchstone_panel(network, "S21", "Smith")
    assert "S22 impedance Smith chart" in str(touchstone_panel(network, "S22", "Smith"))


def test_single_point_match_visible_and_data_unchanged() -> None:
    network = parse_touchstone("# GHz S RI R 50\n1 0 0", "match.s1p")
    before = network.model_dump_json()
    html = str(touchstone_panel(network, "S11", "Smith"))
    assert 'cx="300.000000" cy="290.000000" r="3"' in html
    assert network.model_dump_json() == before
