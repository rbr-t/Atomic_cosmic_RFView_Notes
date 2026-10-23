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
