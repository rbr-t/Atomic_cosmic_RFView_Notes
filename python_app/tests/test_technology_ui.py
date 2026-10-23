import re
from pathlib import Path
from xml.etree import ElementTree

import pytest

from rfview.services import read_guardrails
from rfview.technology_ui import technology_panel

CONFIG = (
    Path(__file__).resolve().parents[2] / "PA design App" / "config" / "technology_guardrails.yaml"
)
NS = {"s": "http://www.w3.org/2000/svg"}


@pytest.mark.parametrize("technology,count", [("all", 6), ("GaN_SiC", 1)])
def test_chart_shapes_units_labels_and_points(technology: str, count: int) -> None:
    panel = str(technology_panel(read_guardrails(CONFIG), technology, "Doherty"))
    svgs = [ElementTree.fromstring(svg) for svg in re.findall(r"<svg.*?</svg>", panel, re.S)]
    assert len(svgs) == 3
    for svg, traces in zip(svgs, (count, count * 2, count), strict=True):
        assert svg.attrib["role"] == "img"
        assert svg.attrib["aria-label"]
        assert svg.find("s:desc", NS) is not None
        assert len(svg.findall("s:polyline", NS)) == traces
        for line in svg.findall("s:polyline", NS):
            assert line.find("s:title", NS) is not None
            points = [tuple(map(float, pair.split(","))) for pair in line.attrib["points"].split()]
            assert len(points) >= 60
            assert all(74.99 <= x <= 725.01 and 39.99 <= y <= 290.01 for x, y in points)
    assert "W/mm" in panel and "PAE (%)" in panel and "Available gain (dB)" in panel
    assert panel.count("<tr>") == count + 1
    assert "Doherty" in panel


def test_catalog_labels_are_escaped() -> None:
    catalog = read_guardrails(CONFIG)
    catalog.technologies["GaN_SiC"].label = '<script>alert("test")</script>'
    panel = str(technology_panel(catalog, "GaN_SiC", "AB"))
    assert "<script>" not in panel
    assert "&lt;script&gt;" in panel


@pytest.mark.parametrize("technology,pa_class", [("unknown", "AB"), ("all", "unknown")])
def test_bad_chart_filters_are_explicit(technology: str, pa_class: str) -> None:
    with pytest.raises(ValueError):
        technology_panel(read_guardrails(CONFIG), technology, pa_class)
