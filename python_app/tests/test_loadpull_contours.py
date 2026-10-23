import re
from pathlib import Path
from types import SimpleNamespace
from xml.etree import ElementTree

import pytest

from rfview.domain.loadpull import LoadPullPoint, parse_loadpull
from rfview.domain.loadpull_contours import loadpull_contours, loadpull_sweeps
from rfview.loadpull_ui import loadpull_panel, sweep_choices
from rfview.services import read_loadpull


def planar_points() -> tuple[LoadPullPoint, ...]:
    return tuple(
        LoadPullPoint(gl_r=x, gl_i=y, pout_dbm=30 + x + 2 * y, pin_dbm=20, freq_ghz=2.4)
        for x, y in ((0, 0), (0.5, 0), (0, 0.5), (0.5, 0.5))
    )


def test_triangle_segments_satisfy_analytic_plane_and_convex_hull() -> None:
    points = planar_points()
    before = [p.model_dump() for p in points]
    segments = loadpull_contours(points, "pout_dbm", (30.25, 30.5, 31))
    assert segments
    assert {s.level for s in segments} == {30.25, 30.5, 31}
    for s in segments:
        for x, y in (s.start, s.end):
            assert 0 <= x <= 0.5 and 0 <= y <= 0.5
            assert 30 + x + 2 * y == pytest.approx(s.level, abs=1e-12)
    assert [p.model_dump() for p in points] == before


def test_no_extrapolation_or_fabricated_flat_surface_contours() -> None:
    assert loadpull_contours(planar_points(), "pout_dbm", (100,)) == ()
    flat = tuple(p.model_copy(update={"pout_dbm": 30}) for p in planar_points())
    assert loadpull_contours(flat, "pout_dbm", (30,)) == ()


@pytest.mark.parametrize(
    "change,match",
    [
        ("duplicate", "Duplicate"),
        ("undefined", "undefined"),
        ("mixed", "one frequency"),
        ("collinear", "triangulated"),
        ("few", "3-2000"),
    ],
)
def test_invalid_contours_fail_without_averaging_or_dropping(change: str, match: str) -> None:
    points = planar_points()
    if change == "duplicate":
        points = (*points, points[0])
    elif change == "undefined":
        points = (points[0].model_copy(update={"pout_dbm": None}), *points[1:])
    elif change == "mixed":
        points = (points[0].model_copy(update={"pin_dbm": 21}), *points[1:])
    elif change == "collinear":
        points = tuple(LoadPullPoint(gl_r=i * 0.1, gl_i=0, pout_dbm=30 + i) for i in range(4))
    else:
        points = points[:2]
    with pytest.raises(ValueError, match=match):
        loadpull_contours(points, "pout_dbm", (30.5,))


def test_metric_and_level_bounds() -> None:
    for metric, levels in (
        ("unknown", (30,)),
        ("pout_dbm", (float("nan"),)),
        ("pout_dbm", ()),
        ("pout_dbm", tuple(range(21))),
    ):
        with pytest.raises(ValueError):
            loadpull_contours(planar_points(), metric, levels)


@pytest.mark.parametrize("field,value", [("gl_r", 1e7), ("pout_dbm", 1e13)])
def test_out_of_range_contour_inputs_are_rejected(field: str, value: float) -> None:
    points = planar_points()
    points = (points[0].model_copy(update={field: value}), *points[1:])
    with pytest.raises(ValueError, match="numeric range"):
        loadpull_contours(points, "pout_dbm", (30.5,))


def test_omitted_triangulation_points_are_not_silently_accepted(monkeypatch) -> None:
    monkeypatch.setattr(
        "rfview.domain.loadpull_contours.Delaunay",
        lambda points: SimpleNamespace(simplices=[[0, 1, 2]]),
    )
    with pytest.raises(ValueError, match="omitted"):
        loadpull_contours(planar_points(), "pout_dbm", (30.5,))


def test_viewer_contour_coordinates_units_table_and_escaping() -> None:
    path = Path(__file__).parent / "fixtures" / "loadpull" / "contour.csv"
    data = read_loadpull(path, "<script>.csv", "amcad")
    html = str(loadpull_panel(data, "sweep-0", "pout_dbm", True))
    assert "<script>" not in html
    assert "dBm" in html and "no extrapolation" in html
    assert html.count('class="smith-point loadpull-point"') == 4
    assert 'class="smith-trace loadpull-contour"' in html
    assert len(loadpull_sweeps(data.points)) == 1
    svg = ElementTree.fromstring(re.search(r"<svg.*?</svg>", html, re.S)[0])
    ns = {"s": "http://www.w3.org/2000/svg"}
    markers = svg.findall("s:circle[@class='smith-point loadpull-point']", ns)
    for marker, point in zip(markers, data.points, strict=True):
        assert float(marker.attrib["cx"]) == pytest.approx(300 + 240 * point.gl_r)
        assert float(marker.attrib["cy"]) == pytest.approx(290 - 240 * point.gl_i)


def test_sweep_grouping_does_not_mix_input_power_or_frequency() -> None:
    text = "GL_R GL_I POUT PIN FREQ\n0 0 30 20 2.4\n0.5 0 31 21 2.4\n0 0.5 32 20 3.5"
    data = parse_loadpull(text, "sweep.spl", "spl")
    assert len(sweep_choices(data)) == 3
    assert "1 selected / 3" in str(loadpull_panel(data, "sweep-0", "pout_dbm"))
    with pytest.raises(ValueError, match="3-2000"):
        loadpull_panel(data, "sweep-0", "pout_dbm", True)
    with pytest.raises(ValueError, match="available"):
        loadpull_panel(data, "sweep-4", "pout_dbm")


def test_viewer_limit_explicit() -> None:
    text = "GL_R GL_I POUT\n" + "\n".join(f"{i / 10000} 0 30" for i in range(2001))
    data = parse_loadpull(text, "large.spl", "spl")
    with pytest.raises(ValueError, match="2000"):
        loadpull_panel(data, "sweep-0", "pout_dbm")
