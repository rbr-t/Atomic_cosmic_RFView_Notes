import math
from pathlib import Path

import pytest

from rfview.domain.loadpull import parse_loadpull
from rfview.loadpull_ui import loadpull_panel

HEADER = (
    "#FUNDAMENTAL FREQUENCY: 2.4 GHz\n#Z0SOURCE: 50\n#Z0LOAD: 75\n"
    "#GAMMASOURCE: 0.1 0\n#GAMMALOAD: 0.5 90\n#HARMONICS: 0\n"
)
ROW = "2400000000 1 .01 20 .2 4 0 2 0 1 0 10 0"
TEXT = HEADER + "#BEGIN\n" + ROW + "\n#END\n"


@pytest.mark.parametrize(
    "normalization,divisor1,divisor2",
    [
        ("peak_voltage", 100, 150),
        ("rms_voltage", 50, 75),
        ("power", 1, 1),
    ],
)
def test_explicit_wave_conventions_and_raw_quantities(normalization, divisor1, divisor2) -> None:
    data = parse_loadpull(TEXT, "test.cst", "cst", cst_wave_normalization=normalization)
    point = data.points[0]
    assert point.pin_w == pytest.approx(12 / divisor1)
    assert point.pout_w == pytest.approx(99 / divisor2)
    assert point.pdc_w == 4
    assert point.gl_i == pytest.approx(0.5)
    assert point.extra["source.z0load"] == 75
    assert point.extra["source.v1_v"] == 1
    assert point.extra["source.b2_real"] == 10
    assert data.metadata["wave_normalization"] == normalization
    assert any("declared interpretation" in w for w in data.warnings)
    html = str(loadpull_panel(data, "sweep-0", "pout_dbm"))
    assert 'id="cst_wave_table"' in html and "CST net wave powers" in html
    assert normalization in html


def test_pre_and_post_begin_metadata_are_equivalent_and_do_not_leak() -> None:
    outside = parse_loadpull(TEXT, "outside.cst", "cst")
    inside = parse_loadpull("#BEGIN\n" + HEADER + ROW + "\n#END", "inside.cst", "cst")
    assert outside.points == inside.points
    with pytest.raises(ValueError, match="own load Gamma"):
        parse_loadpull(TEXT + "#BEGIN\n" + ROW + "\n#END", "leak.cst", "cst")


@pytest.mark.parametrize(
    "text,match",
    [
        (TEXT.replace("#END", ""), "Unclosed"),
        (TEXT + HEADER, "no following"),
        (TEXT.replace("#Z0LOAD: 75", "#Z0LOAD: 75\n#Z0LOAD: 50"), "duplicate"),
        (TEXT.replace("#HARMONICS: 0", "#HARMONICS: 2"), "harmonic"),
        (TEXT.replace(ROW, ROW + "\n#Z0LOAD: 50"), "cannot change"),
        (TEXT.replace(ROW, ""), "empty"),
        (TEXT.replace("2400000000", "2500000000"), "mismatched"),
        (TEXT.replace(" 10 0", " nan 0"), "nonfinite"),
        (TEXT.replace("2400000000", "NaN"), "header or measurement"),
    ],
)
def test_bad_block_state_and_measurements_rejected(text, match) -> None:
    with pytest.raises(ValueError, match=match):
        parse_loadpull(text, "bad.cst", "cst")


def test_selection_checks_unselected_data_and_missing_references_warn() -> None:
    data = parse_loadpull(TEXT + TEXT, "two.cst", "cst", cst_block_index=2)
    assert len(data.points) == 1
    assert data.metadata["total_source_rows"] == "2"
    assert data.points[0].extra["source.block_index"] == 2
    for index in (0, 3, True):
        with pytest.raises(ValueError):
            parse_loadpull(TEXT, "bad.cst", "cst", cst_block_index=index)
    with pytest.raises(ValueError, match="normalization"):
        parse_loadpull(TEXT, "bad.cst", "cst", cst_wave_normalization="unknown")
    with pytest.raises(ValueError, match="nonfinite"):
        parse_loadpull(TEXT + TEXT.replace(" 10 0", " inf 0"), "bad.cst", "cst", cst_block_index=1)
    missing = parse_loadpull(TEXT.replace("#Z0LOAD: 75\n", ""), "missing.cst", "cst")
    assert any("missing z0load" in w for w in missing.warnings)


def test_repository_every_block_and_wave_power_matches_source() -> None:
    root = Path(__file__).resolve().parents[2] / "PA design App" / "data" / "sample-files"
    source = next(root.glob("*.cst"))
    text = source.read_text(encoding="utf-8-sig")
    data = parse_loadpull(text, source.name, "cst")
    rows = [
        [float(token) for token in line.split()]
        for line in text.splitlines()
        if line.strip() and line.lstrip()[0] in "+-0123456789"
    ]
    assert len(data.points) == len(rows)
    assert data.metadata["total_blocks"] == "365"
    assert len(rows) == 8915
    for point, values in zip(data.points, rows, strict=True):
        # Repository declares distinct, explicitly stored 5-ohm references on both ports.
        assert point.extra["source.z0source"] == point.extra["source.z0load"] == 5
        pin = (values[5] ** 2 + values[6] ** 2 - values[7] ** 2 - values[8] ** 2) / 10
        pout = (values[11] ** 2 + values[12] ** 2 - values[9] ** 2 - values[10] ** 2) / 10
        assert point.pin_w == pytest.approx(pin)
        assert point.pout_w == pytest.approx(pout)
        assert point.pdc_w == pytest.approx(values[3] * values[4])
        assert point.freq_ghz == values[0] / 1e9
        if pin > 0 and pout > 0:
            assert point.gain_db == pytest.approx(10 * math.log10(pout / pin))
    selected = parse_loadpull(text, source.name, "cst", cst_block_index=365)
    assert selected.points == tuple(p for p in data.points if p.extra["source.block_index"] == 365)
