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
