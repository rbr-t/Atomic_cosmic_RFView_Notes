#!/usr/bin/env python3
"""
rf_to_dxf.py — Convert RF CAD design JSON to DXF.
Usage: python3 rf_to_dxf.py <input.json> <output.dxf>

Each component is drawn as a closed LWPOLYLINE (rectangle) on a layer
named after its metal layer (metal_top, metal_bot, metal_inner_1, metal_inner_2).
Vias are drawn as CIRCLEs. Ports are drawn as POINT + small cross.
All coordinates are in mm. Origin = (0, 0).
"""

import sys
import json
import math
import ezdxf
from ezdxf import units

# ── DXF layer colour indices (AutoCAD standard indices) ──────────────────────
LAYER_COLOR = {
    "metal_top":     2,   # yellow
    "metal_bot":     5,   # blue
    "metal_inner_1": 3,   # green
    "metal_inner_2": 6,   # magenta
    "via":           1,   # red
    "port":          4,   # cyan
}

def rotation_matrix(deg):
    r = math.radians(deg)
    return math.cos(r), -math.sin(r), math.sin(r), math.cos(r)

def rotate_pts(pts, cx, cy, deg):
    cos_r, sin_r = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    out = []
    for x, y in pts:
        dx, dy = x - cx, y - cy
        out.append((cx + dx * cos_r - dy * sin_r,
                    cy + dx * sin_r + dy * cos_r))
    return out

def rect_pts(cx, cy, w, h):
    hw, hh = w / 2, h / 2
    return [
        (cx - hw, cy - hh),
        (cx + hw, cy - hh),
        (cx + hw, cy + hh),
        (cx - hw, cy + hh),
    ]

def add_component(msp, comp):
    ctype  = comp.get("type", "ms")
    layer  = comp.get("layer", "metal_top")
    rot    = comp.get("rotation", 0)
    params = comp.get("params", {})

    # Canvas uses pixels; scale factor: assumed 10 px/mm in canvas default grid
    # The canvas state stores x/y in pixels but we need the real mm position.
    # The JSON exports x/y as canvas px, W/L are stored in params as mm.
    # We use x/y directly as mm (the canvas already uses mm as its unit space
    # at scale=1 px/mm when grid is 1mm).  If mismatch shows up users can
    # adjust the SCALE constant.
    SCALE = 1.0   # px-to-mm  (canvas coordinate space = mm)
    cx = comp.get("x", 0) * SCALE
    cy = comp.get("y", 0) * SCALE

    W = float(params.get("W", 1.0))
    L = float(params.get("L", 10.0))

    dxf_layer = layer if layer in LAYER_COLOR else "metal_top"
    color     = LAYER_COLOR[dxf_layer]

    if ctype in ("ms", "open_stub", "short_stub"):
        pts = rect_pts(cx, cy, W, L)
        pts = rotate_pts(pts, cx, cy, rot)
        msp.add_lwpolyline(pts, close=True,
                           dxfattribs={"layer": dxf_layer, "color": color})

    elif ctype == "bend90":
        # Two rectangular arms meeting at corner
        arm1 = rect_pts(cx - L / 4, cy, W, L / 2)
        arm2 = rect_pts(cx, cy + L / 4, W, L / 2)
        for pts in (arm1, arm2):
            pts = rotate_pts(pts, cx, cy, rot)
            msp.add_lwpolyline(pts, close=True,
                               dxfattribs={"layer": dxf_layer, "color": color})

    elif ctype == "tee":
        # Horizontal bar + vertical stem
        bar  = rect_pts(cx, cy, L, W)
        stem = rect_pts(cx, cy - L / 4, W, L / 2)
        for pts in (bar, stem):
            pts = rotate_pts(pts, cx, cy, rot)
            msp.add_lwpolyline(pts, close=True,
                               dxfattribs={"layer": dxf_layer, "color": color})

    elif ctype == "coupled":
        gap = float(params.get("gap", 0.2))
        # Two parallel lines
        off = (W + gap) / 2
        line1 = rect_pts(cx - off, cy, W, L)
        line2 = rect_pts(cx + off, cy, W, L)
        for pts in (line1, line2):
            pts = rotate_pts(pts, cx, cy, rot)
            msp.add_lwpolyline(pts, close=True,
                               dxfattribs={"layer": "metal_top", "color": LAYER_COLOR["metal_top"]})

    elif ctype == "via":
        drill = float(params.get("drill", 0.3)) / 2
        pad   = float(params.get("pad",   0.6)) / 2
        msp.add_circle((cx, cy), pad,
                       dxfattribs={"layer": "via", "color": LAYER_COLOR["via"]})
        msp.add_circle((cx, cy), drill,
                       dxfattribs={"layer": "via", "color": LAYER_COLOR["via"]})

    elif ctype == "port":
        port_w, port_l = W, L
        pts = rect_pts(cx, cy, port_w, port_l)
        pts = rotate_pts(pts, cx, cy, rot)
        msp.add_lwpolyline(pts, close=True,
                           dxfattribs={"layer": "port", "color": LAYER_COLOR["port"]})
        # Port marker cross
        hs = min(port_w, port_l) * 0.3
        msp.add_line((cx - hs, cy), (cx + hs, cy),
                     dxfattribs={"layer": "port", "color": LAYER_COLOR["port"]})
        msp.add_line((cx, cy - hs), (cx, cy + hs),
                     dxfattribs={"layer": "port", "color": LAYER_COLOR["port"]})

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.json> <output.dxf}", file=sys.stderr)
        sys.exit(1)

    in_json  = sys.argv[1]
    out_dxf  = sys.argv[2]

    with open(in_json, "r") as f:
        design = json.load(f)

    doc = ezdxf.new("R2010")
    doc.units = units.MM
    msp = doc.modelspace()

    # Create layers
    for lname, color in LAYER_COLOR.items():
        if lname not in doc.layers:
            doc.layers.add(lname, dxfattribs={"color": color})

    components = design.get("components", [])
    for comp in components:
        try:
            add_component(msp, comp)
        except Exception as e:
            print(f"Warning: skipped component {comp.get('name','?')}: {e}",
                  file=sys.stderr)

    # Title block attribute in HEADER
    doc.header["$ACADVER"] = "AC1024"
    doc.saveas(out_dxf)
    print(f"Written: {out_dxf}")

if __name__ == "__main__":
    main()
