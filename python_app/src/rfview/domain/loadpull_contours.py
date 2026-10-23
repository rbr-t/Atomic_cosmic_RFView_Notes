"""Piecewise-linear contours on a measured Delaunay triangulation, without extrapolation."""

import math
from typing import Literal

from pydantic import BaseModel, ConfigDict
from scipy.spatial import Delaunay, QhullError

from rfview.domain.loadpull import LoadPullPoint

LoadPullMetric = Literal["pout_dbm", "gain_db", "pae_pct", "de_pct"]
METRICS = {
    "pout_dbm": ("Output power", "dBm"),
    "gain_db": ("Transducer gain", "dB"),
    "pae_pct": ("Power-added efficiency", "%"),
    "de_pct": ("Drain efficiency", "%"),
}
MAX_CONTOUR_POINTS = 2000
SweepKey = tuple[float | None, float | None, float | None, float | None, float | None]


def sweep_key(point: LoadPullPoint) -> SweepKey:
    return (point.freq_ghz, point.pin_dbm, point.gs_r, point.gs_i, point.vdc_v)


def loadpull_sweeps(points: tuple[LoadPullPoint, ...]) -> dict[SweepKey, tuple[LoadPullPoint, ...]]:
    grouped: dict[SweepKey, list[LoadPullPoint]] = {}
    for point in points:
        grouped.setdefault(sweep_key(point), []).append(point)
    return {key: tuple(value) for key, value in grouped.items()}


class ContourSegment(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    level: float
    start: tuple[float, float]
    end: tuple[float, float]


def loadpull_contours(
    points: tuple[LoadPullPoint, ...],
    metric: LoadPullMetric,
    levels: tuple[float, ...],
    *,
    backoff_db: float | None = None,
) -> tuple[ContourSegment, ...]:
    if metric not in METRICS:
        raise ValueError("Unsupported load-pull contour metric")
    if not 3 <= len(points) <= MAX_CONTOUR_POINTS:
        raise ValueError(f"Contours require 3-{MAX_CONTOUR_POINTS} measurement points")
    if backoff_db is not None:
        if (
            not math.isfinite(backoff_db)
            or len({p.freq_ghz for p in points}) != 1
            or any(
                p.extra.get("source.bo") is None
                or not math.isclose(p.extra["source.bo"] or 0, backoff_db, rel_tol=0, abs_tol=1e-8)
                for p in points
            )
        ):
            raise ValueError("Choose one frequency and matching source BO for ALPS contours")
    elif len({sweep_key(p) for p in points}) != 1:
        raise ValueError("Choose one frequency/input-power/source-Gamma/bias sweep for contours")
    if not 1 <= len(levels) <= 20 or not all(math.isfinite(level) for level in levels):
        raise ValueError("Contours require 1-20 finite levels")
    coordinates = [(p.gl_r, p.gl_i) for p in points]
    if len(set(coordinates)) != len(coordinates):
        raise ValueError(
            "Duplicate load coordinates: separate repeated/hidden sweeps before contouring"
        )
    values: list[float] = []
    for p in points:
        value: float | None = getattr(p, metric)
        if value is None:
            raise ValueError(
                f"Contour metric {metric} is undefined at a measurement; no points dropped"
            )
        if not math.isfinite(value):
            raise ValueError("Contour values must be finite")
        if abs(value) > 1e12:
            raise ValueError("Contour metric exceeds the supported numeric range")
        values.append(value)
    if max(abs(v) for xy in coordinates for v in xy) > 1e6:
        raise ValueError("Contour Gamma coordinates exceed the supported numeric range")
    try:
        triangles = Delaunay(coordinates).simplices
    except QhullError as exc:
        raise ValueError(
            "Load coordinates cannot be triangulated (collinear/degenerate geometry)"
        ) from exc
    if {int(index) for triangle in triangles for index in triangle} != set(range(len(points))):
        raise ValueError(
            "Triangulation omitted numerically degenerate points; no measurements dropped"
        )
    segments: list[ContourSegment] = []
    for triangle in triangles:
        indices = tuple(int(index) for index in triangle)
        for level in levels:
            crossings: list[tuple[float, float]] = []
            for first, second in ((0, 1), (1, 2), (2, 0)):
                a, b = indices[first], indices[second]
                va, vb = values[a], values[b]
                # Half-open crossings avoid double-counting vertices and flat edges.
                if not (va <= level < vb or vb <= level < va):
                    continue
                ratio = (level - va) / (vb - va)
                x = coordinates[a][0] * (1 - ratio) + coordinates[b][0] * ratio
                y = coordinates[a][1] * (1 - ratio) + coordinates[b][1] * ratio
                crossings.append((x, y))
            if len(crossings) == 2 and crossings[0] != crossings[1]:
                segments.append(ContourSegment(level=level, start=crossings[0], end=crossings[1]))
    return tuple(segments)
