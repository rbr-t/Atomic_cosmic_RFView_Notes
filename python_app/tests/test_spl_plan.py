import math
from pathlib import Path

import pytest

from rfview.domain import spl_plan
from rfview.domain.loadpull import LoadPullData, parse_loadpull
from rfview.domain.spl_plan import parse_spl_plan
from rfview.services import read_spl_plan

HEADER = (
    "valid gamma_src1 gamma_ld1 Freq Pin_avail_dBm Pout_dBm Gt_dB "
    "Iq_out_mA Vq_in_v Vout_v Iout_mA Vin_v Eff_% Eff_col Pdis PoutW"
)
HARMONICS = "num_src_harmonics = 1, num_ld_harmonics = 1"
ROW = "1 0.1 0.2 0.3 -0.4 1.75 20 40 20 1800 0 30 1000 1.1 30 35 99 9"
PREAMBLE = (
    "! Power sweep plan data file\nNumber of Frequencies = 2\nNumber of Variables = 2\n"
    "VAR=<F1 Load Gamma>, Units=<>\nVAR=<Pin_avail>, Units=<dBm>\n"
    "! Freq Points per VAR\n1.75 1 2\n1.8 1 1\n"
    "User params= 3\nUser names: Eff_col Pdis PoutW\nUser units: % W W\n"
)


def sample() -> str:
    return (
        f"{PREAMBLE}\nFreq = 1.75 GHz\n{HARMONICS}\n{HEADER}\n{ROW}\n0\n"
        f"Freq = 1800 MHz\n{HARMONICS}\n{HEADER}\n{ROW.replace('1.75', '1.8')}\n"
    )


def test_profile_preserves_distinct_columns_and_declared_invalid_slots() -> None:
    result = parse_spl_plan(sample(), r"C:\sample.spl")
    point = result.dataset.points[0]
    assert result.dataset.filename == "sample.spl"
    assert (point.gl_r, point.gl_i, point.gs_r, point.gs_i) == (0.3, -0.4, 0.1, 0.2)
    assert (point.pin_dbm, point.pout_dbm, point.gain_db) == (20, 40, 20)
    assert (point.idc_a, point.vdc_v, point.pdc_w) == (1, 30, 30)
    assert (point.pout_w, point.pin_w, point.pae_pct, point.de_pct) == (10, 0.1, 33, 35)
    assert point.extra["source.poutw"] == 9
    assert point.extra["source.pdis"] == 99
    assert point.extra["source.eff_%"] == 30
    assert point.extra["source.iq_out_ma"] == 1800
    assert point.extra["source.vq_in_v"] == 0
    assert point.extra["source.slot_index"] == 1
    assert point.extra["source.section_index"] == 1
    assert result.sections[0].invalid_rows == 1
    assert result.dataset.metadata["total_source_slots"] == "3"
    assert any("VALID=0" in warning for warning in result.dataset.warnings)
    assert LoadPullData.model_validate_json(result.dataset.model_dump_json()) == result.dataset
    second = parse_spl_plan(sample(), "sample.spl", section_index=2)
    assert len(second.dataset.points) == 1
    assert second.dataset.points[0].freq_ghz == 1.8
    assert second.dataset.points[0].extra["source.section_index"] == 2


@pytest.mark.parametrize(
    "old,new,match",
    [
        ("Number of Frequencies = 2", "Number of Frequencies = 3", "declared count"),
        ("Number of Frequencies = 2", "Number of Frequencies = 1001", "frequency-section"),
        ("1.8 1 1", "1.8 1 1\n1.9 1 1", "more table rows"),
        ("Number of Variables = 2", "Number of Variables = 3", "profile"),
        ("User units: % W W", "User units: fraction W W", "profile"),
        ("Units=<dBm>", "Units=<W>", "profile"),
        ("User names: Eff_col Pdis PoutW", "User names: Eff_col Pdc PoutW", "profile"),
        ("User params= 3", "User params= 3\nUser params= 3", "duplicate"),
        ("1.8 1 1", "1.75 1 1", "duplicate/invalid"),
        ("1.75 1 2", "1.75 0 2", "duplicate/invalid"),
        ("1.75 1 2", "1.75 1 3", "slot count mismatch"),
        ("1.75 1 2", "1.75 1 1", "too many"),
        ("1.75 1 2", "1.75 100001 1", "source-slot"),
        ("Freq = 1800 MHz", "Freq = 1900 MHz", "disagrees"),
        ("num_src_harmonics = 1", "num_src_harmonics = 2", "fundamental"),
        ("num_ld_harmonics = 1", "num_ld_harmonics = 0", "fundamental"),
        ("Eff_% Eff_col Pdis PoutW", "Eff_% Eff_col PDC PoutW", "unsupported measurement"),
        ("Eff_% Eff_col Pdis PoutW", "Eff_% Eff_col Pdis Eff_col", "distinct"),
        ("20 40 20", "20 nan 20", "nonfinite"),
        ("20 40 20", "20 1e100 20", "numeric range"),
        ("20 40 20", "20 NA 20", "missing numeric"),
        ("20 40 20", "20 bad 20", "numeric token"),
        ("1 0.1", "2 0.1", "VALID"),
        ("1.75 20 40", "1.9 20 40", "frequency mismatch"),
        ("30 1000 1.1", "30 1000", "expected 18"),
        ("User params= 3", "unrecognized metadata", "unrecognized preamble"),
        ("\n0\n", "\n0 0\n", "expected 18"),
    ],
)
def test_malformed_plans_are_explicitly_rejected(old: str, new: str, match: str) -> None:
    with pytest.raises(ValueError, match=match):
        parse_spl_plan(sample().replace(old, new), "bad.spl")


def test_bad_unselected_sections_are_not_ignored() -> None:
    text = sample()
    # Only the second section is damaged; the first selected section remains valid.
    tail = text.rfind("20 40 20")
    damaged = text[:tail] + text[tail:].replace("20 40 20", "20 nan 20", 1)
    with pytest.raises(ValueError, match="nonfinite"):
        parse_spl_plan(damaged, "bad.spl", section_index=1)
    with pytest.raises(ValueError, match="missing declared"):
        parse_spl_plan(text[: text.index("Freq = 1800")], "truncated.spl")


def test_selected_rows_keep_original_slot_indices_and_anomalies() -> None:
    text = sample().replace(f"{ROW}\n0", f"0\n{ROW}")
    result = parse_spl_plan(text, "index.spl")
    assert result.dataset.points[0].extra["source.slot_index"] == 2
    anomaly = parse_spl_plan(sample().replace("30 35 99", "130 135 99"), "anomaly.spl")
    assert anomaly.dataset.points[0].de_pct == 135
    assert any("outside 0-100" in warning for warning in anomaly.dataset.warnings)


@pytest.mark.parametrize("index", [0, -1, 3, True, 1.5])
def test_invalid_section_selection_is_rejected(index) -> None:
    with pytest.raises(ValueError):
        parse_spl_plan(sample(), "sample.spl", section_index=index)


def test_invalid_slots_are_counted_not_fabricated_and_no_valid_rows_is_rejected() -> None:
    result = parse_spl_plan(
        sample().replace("\n0\n", f"\n{ROW.replace('1 0.1', '0 0.1')}\n"), "full-invalid.spl"
    )
    assert len(result.dataset.points) == 1 and result.sections[0].invalid_rows == 1
    with pytest.raises(ValueError, match="no valid measurement"):
        parse_spl_plan(sample().replace(ROW, "0", 1), "empty.spl")


def test_byte_and_selected_row_bounds(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    source = tmp_path / "plan.spl"
    source.write_text(sample(), encoding="utf-8")
    monkeypatch.setattr(spl_plan, "MAX_SPL_PLAN_VIEW_POINTS", 1)
    with pytest.raises(ValueError, match="no rows dropped"):
        parse_spl_plan(sample().replace("\n0\n", f"\n{ROW}\n"), "two.spl")
    with pytest.raises(ValueError, match="5 MiB"):
        parse_spl_plan(" " * (5 * 1024 * 1024 + 1), "big.spl")
    source.write_bytes(b" " * (5 * 1024 * 1024 + 1))
    with pytest.raises(ValueError, match="5 MiB"):
        read_spl_plan(source, source.name)


def test_generic_spl_contract_is_unchanged_and_not_implicitly_profiled() -> None:
    generic = parse_loadpull(
        "GL_R GL_I DE\n0 0 .5", "generic.spl", "spl", efficiency_unit="fraction"
    )
    assert generic.points[0].de_pct == 50
    with pytest.raises(ValueError, match="Unsupported"):
        parse_loadpull(sample(), "plan.spl", "spl_plan")


def test_repository_plan_all_sections_every_valid_row_matches_source_columns() -> None:
    root = Path(__file__).resolve().parents[2] / "PA design App" / "data" / "sample-files"
    source = next(root.glob("*.spl"))
    text = source.read_text(encoding="utf-8-sig")
    raw_sections = text.split("Freq = ")[1:]
    valid_counts = [811, 632, 796, 688, 757, 672, 505, 570]
    invalid_counts = [260, 250, 338, 299, 356, 315, 251, 291]
    for index, raw_section in enumerate(raw_sections, 1):
        result = read_spl_plan(source, source.name, section_index=index)
        assert [s.valid_rows for s in result.sections] == valid_counts
        assert [s.invalid_rows for s in result.sections] == invalid_counts
        assert result.dataset.metadata["total_source_slots"] == "7791"
        assert result.dataset.metadata["total_valid_rows"] == "5431"
        assert result.dataset.metadata["total_invalid_rows"] == "2360"
        lines = raw_section.splitlines()
        measured = [
            (slot, [float(v) for v in line.split()])
            for slot, line in enumerate((line for line in lines[3:] if line.strip()), 1)
            if line.split()[0] == "1"
        ]
        assert len(result.dataset.points) == len(measured) == valid_counts[index - 1]
        for point, (slot, row) in zip(result.dataset.points, measured, strict=True):
            assert (point.gs_r, point.gs_i, point.gl_r, point.gl_i) == tuple(row[1:5])
            assert point.freq_ghz == row[5]
            assert (point.pin_dbm, point.pout_dbm, point.gain_db) == tuple(row[6:9])
            assert point.idc_a == row[12] / 1000
            assert point.vdc_v == row[11]
            assert point.pdc_w == pytest.approx(row[11] * row[12] / 1000)
            assert point.de_pct == row[15]
            expected_pae = (
                (10 ** ((row[7] - 30) / 10) - 10 ** ((row[6] - 30) / 10))
                / (row[11] * row[12] / 1000)
                * 100
            )
            assert point.pae_pct == pytest.approx(expected_pae)
            assert point.extra["source.iq_out_ma"] == row[9]
            assert point.extra["source.vq_in_v"] == row[10]
            assert point.extra["source.eff_%"] == row[14]
            assert point.extra["source.pdis"] == row[16]
            assert point.extra["source.poutw"] == row[17]
            assert point.extra["source.slot_index"] == slot
            assert math.isfinite(point.pae_pct or 0)
