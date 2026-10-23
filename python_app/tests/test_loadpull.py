import hashlib
import json
from pathlib import Path

import pytest

from rfview.domain.loadpull import parse_loadpull

FIXTURES = Path(__file__).parent / "fixtures"
REFERENCE = json.loads((FIXTURES / "loadpull_reference.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("case", REFERENCE["cases"], ids=lambda case: case["format"])
def test_vendor_fixture_matches_legacy_r(case: dict) -> None:
    path = FIXTURES / "loadpull" / case["filename"]
    assert hashlib.md5(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() == case["fixture_md5"]
    result = parse_loadpull(path.read_text(encoding="utf-8"), path.name, case["format"])
    assert len(result.points) == len(case["points"])
    for point, expected in zip(result.points, case["points"], strict=True):
        for key, value in expected.items():
            actual = getattr(point, key)
            if value is None:
                assert actual is None, key
            else:
                assert actual == pytest.approx(value, rel=1e-10, abs=1e-12), key
    assert result.warnings
    json.dumps(result.model_dump(), allow_nan=False)


def test_per_block_spl_frequency_is_not_relabelled_with_final_frequency() -> None:
    result = parse_loadpull(
        "GL_R GL_I POUT\nFreq = 2400 MHz\n0 0 30\nFreq = 3.5 GHz\n0.2 0 31",
        "multifrequency.spl",
        "spl",
    )
    assert [p.freq_ghz for p in result.points] == [2.4, 3.5]


def test_repeated_expanded_spl_header_and_compact_frequency_metadata() -> None:
    data = parse_loadpull(
        "Freq=2400 MHz\nGAMMA_SRC1 GAMMA_LD1 POUT\n0 0 0.1 0.2 30\n"
        "Freq=3.5 GHz\nGAMMA_SRC1 GAMMA_LD1 POUT\n0 0 0.3 0.4 31",
        "repeat.spl",
        "spl",
    )
    assert [(p.freq_ghz, p.gl_r, p.gl_i) for p in data.points] == [
        (2.4, 0.1, 0.2),
        (3.5, 0.3, 0.4),
    ]


def test_explicit_efficiency_units_and_anomalies_do_not_repair_measurements() -> None:
    text = "GL_R,GL_I,POUT,PAE,DE\n1.1,0,30,0.5,0.7"
    percent = parse_loadpull(text, "test.csv", "amcad")
    fraction = parse_loadpull(text, "test.csv", "amcad", efficiency_unit="fraction")
    assert percent.points[0].pae_pct == 0.5
    assert fraction.points[0].pae_pct == 50
    assert any("|Gamma_load| > 1" in w for w in percent.warnings)
    anomaly = parse_loadpull("GL_R GL_I PAE DE\n0 0 120 110", "bad.spl", "spl")
    assert anomaly.points[0].pae_pct == 120
    assert anomaly.points[0].de_pct == 110
    assert any("PAE exceeds DE" in w for w in anomaly.warnings)


def test_derived_power_efficiency_current_and_extra_columns() -> None:
    result = parse_loadpull(
        "GL_MAG GL_ANG PIN POUT VDS IDC(MA) AM_PM\n0.5 90 20 30 20 100 3",
        "derived.spl",
        "spl",
    )
    point = result.points[0]
    assert point.gl_r == pytest.approx(0, abs=1e-12)
    assert point.gl_i == pytest.approx(0.5)
    assert point.idc_a == 0.1
    assert point.pdc_w == 2
    assert point.pout_w == 1
    assert point.pin_w == 0.1
    assert point.pae_pct == 45
    assert point.de_pct == 50
    assert point.extra["am_pm"] == 3


@pytest.mark.parametrize(
    "text,format,match",
    [
        ("GL_R GL_I\n0", "spl", "expected 2"),
        ("GL_R GL_I\n0 0 1", "spl", "expected 2"),
        ("GL_R GL_I\nNaN 0", "spl", "nonfinite"),
        ("GL_R GL_I\nBAD 0", "spl", "numeric"),
        ("GL_R POUT\n0.2 30", "spl", "incomplete"),
        ("POUT GAIN\n30 10", "spl", "required"),
        ("GL_R GL_I GL_RE\n0 0 0", "spl", "ambiguous"),
        ("BEGIN DATA\nGL_R GL_I\n0 0", "mdf", "Unclosed"),
        ("BEGIN DATA\nGL_R GL_I\n0 0\nEND DATA", "mdif", "invalid data block"),
        ("! Point Gamma Phase Pin Pout\n20 30", "lpcwave", "descriptor"),
        ("GL_R GL_I POUT\n0 0 1e308", "spl", "numeric range"),
        ("GL_R GL_I FREQ\n0 0 -1", "spl", "frequency"),
        (
            "BEGIN SWEEP\n% GL_R(real) GL_I(real) FNAME(string)\n0 0 file\nEND SWEEP",
            "mdf",
            "string",
        ),
    ],
)
def test_bad_records_are_explicit_not_silently_dropped(text: str, format: str, match: str) -> None:
    with pytest.raises(ValueError, match=match):
        parse_loadpull(text, "bad", format)


def test_optional_missing_values_and_undefined_efficiency() -> None:
    result = parse_loadpull("GL_R GL_I PIN POUT PDC\n0 0 NA 30 0", "missing.spl", "spl")
    assert result.points[0].pin_dbm is None
    assert result.points[0].pae_pct is None
    assert result.points[0].de_pct is None
    assert any("nonpositive DC" in w for w in result.warnings)


def test_cst_independent_voltage_wave_equations_and_port_references() -> None:
    path = FIXTURES / "loadpull" / "reference.cst"
    text = path.read_text(encoding="utf-8")
    point = parse_loadpull(text, path.name, "cst").points[0]
    assert point.pin_w == pytest.approx((16 - 4) / 100)
    assert point.pout_w == pytest.approx((100 - 1) / 100)
    assert point.gain_db == pytest.approx(9.1645394855)
    assert point.pae_pct == pytest.approx((0.99 - 0.12) / 4 * 100)
    assert point.gl_i == pytest.approx(0.5)
    assert point.freq_ghz == 2.4
    unequal = parse_loadpull(text.replace("#Z0LOAD: 50", "#Z0LOAD: 75"), "unequal.cst", "cst")
    assert unequal.points[0].pout_w == pytest.approx(99 / 150)
    assert unequal.points[0].pin_w == point.pin_w


@pytest.mark.parametrize(
    "old,new,match",
    [
        ("#END", "", "Unclosed"),
        ("#Z0SOURCE: 50", "#Z0SOURCE: 0", "positive"),
        ("2400000000", "2500000000", "mismatched"),
        (" 10 0", " 10", "13 numeric"),
    ],
)
def test_cst_invalid_data_is_rejected(old: str, new: str, match: str) -> None:
    text = (FIXTURES / "loadpull" / "reference.cst").read_text(encoding="utf-8")
    with pytest.raises(ValueError, match=match):
        parse_loadpull(text.replace(old, new), "bad.cst", "cst")


def test_explicit_format_and_unit_selection_and_byte_limit() -> None:
    for format, unit in [("other", "percent"), ("spl", "auto")]:
        with pytest.raises(ValueError):
            parse_loadpull("GL_R GL_I\n0 0", "test", format, efficiency_unit=unit)
    with pytest.raises(ValueError, match="5 MiB"):
        parse_loadpull(" " * (5 * 1024 * 1024 + 1), "test", "spl")


def test_source_revision() -> None:
    path = (
        Path(__file__).resolve().parents[2]
        / "PA design App"
        / "src"
        / "modules"
        / "rf_tools"
        / "lp_parsers.R"
    )
    assert (
        hashlib.md5(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        == REFERENCE["provenance"]["source_md5"]
    )


def test_repository_lpcwave_samples_preserve_every_numeric_measurement_and_harmonics() -> None:
    root = Path(__file__).resolve().parents[2] / "PA design App" / "data" / "sample-files"
    samples = sorted(root.glob("*.lpcwave"))
    assert len(samples) == 2
    counts = []
    for path in samples:
        text = path.read_text(encoding="utf-8-sig")
        numeric_rows = [
            line.split()
            for line in text.splitlines()
            if line.strip() and line.lstrip()[0] in "-+0123456789"
        ]
        result = parse_loadpull(text, path.name, "lpcwave")
        assert len(result.points) == len(numeric_rows)
        counts.append(len(result.points))
        for point, source in zip(result.points, numeric_rows, strict=True):
            assert point.freq_ghz == 2.6
            assert point.pin_dbm == float(source[1])
            assert point.pout_dbm == float(source[2])
            assert point.gain_db == float(source[3])
            assert "a1ref1" in point.extra and "b2imf2" in point.extra
        result.model_dump_json()
    assert sorted(counts) == [865, 869]
