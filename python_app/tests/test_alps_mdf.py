import csv
import math
from pathlib import Path

import pytest

from rfview.domain import alps_mdf
from rfview.domain.alps_mdf import read_alps_lines
from rfview.domain.loadpull import LoadPullData
from rfview.domain.loadpull_contours import loadpull_contours
from rfview.loadpull_ui import loadpull_panel, sweep_choices
from rfview.services import read_alps_mdf

NAMES = (
    "BO Pin_avail_dBm Pout_dBm Gt_dB Freq Eff_col Vout_v Iout_mA "
    "GLRE GLIM GSRE GSIM gamma_ld1_re gamma_ld1_im gamma_src1_re gamma_src1_im "
    "Pdis Iq_out_mA Vq_in_v PAE_compr PoutW"
).split()
HEADER = "% " + " ".join(f"{name}(real)" for name in NAMES) + " FNAME(string)"
ROW = (
    "-10 20 40 20 1.8 50 30 1000 .2 .3 .1 .05 -.8 -.1 -.5 -.2 10 1800 0 90 9 "
    '"test path/file ""x"" name"'
)


def block(row: str = ROW, header: str = HEADER) -> str:
    return f"VAR GRE(real) = 0.2\nBEGIN Sweep\n{header}\n{row}\nEND\n"


def parse(text: str, index: int = 1, plane: alps_mdf.AlpsPlane = "dut") -> alps_mdf.AlpsImport:
    return read_alps_lines(
        iter(text.splitlines(keepends=True)), "sample.mdf", plane=plane, block_index=index
    )


def test_explicit_mapping_preserves_alternative_columns_strings_and_derived_dc() -> None:
    result = parse(block())
    point = result.dataset.points[0]
    assert (point.gl_r, point.gl_i, point.gs_r, point.gs_i) == (0.2, 0.3, 0.1, 0.05)
    assert (point.pin_dbm, point.pout_dbm, point.gain_db) == (20, 40, 20)
    assert (point.idc_a, point.vdc_v, point.pdc_w) == (1, 30, 30)
    assert point.de_pct == 50
    assert point.pae_pct == pytest.approx(33)
    assert point.extra["source.pdis"] == 10
    assert point.extra["source.iq_out_ma"] == 1800
    assert point.extra["source.poutw"] == 9
    assert point.source_strings["fname"] == 'test path/file "x" name'
    assert LoadPullData.model_validate_json(result.dataset.model_dump_json()) == result.dataset
    instrument = parse(block(), plane="instrument").dataset.points[0]
    assert (instrument.gl_r, instrument.gl_i, instrument.gs_r, instrument.gs_i) == (
        -0.8,
        -0.1,
        -0.5,
        -0.2,
    )


def test_stream_retains_only_selected_block_but_counts_all_and_rejects_bad_unselected() -> None:
    result = parse(block() + block(ROW.replace("40 20 1.8", "41 21 1.8")), 2)
    assert result.total_rows == 2 and len(result.blocks) == 2
    assert len(result.dataset.points) == 1 and result.dataset.points[0].pout_dbm == 41
    assert result.blocks[1].variables == {"GRE": 0.2}
    with pytest.raises(ValueError, match="nonfinite"):
        parse(block() + block(ROW.replace("-10", "nan")))


def test_fixed_backoff_retains_every_matching_load_without_interpolation() -> None:
    text = block(ROW + "\n" + ROW.replace("-10", "-9.9")) + block()
    result = read_alps_lines(
        text.splitlines(), "sample.mdf", plane="instrument", block_index=1, backoff_db=-10
    )
    assert result.total_rows == 3 and len(result.dataset.points) == 2
    assert [p.extra["source.block_index"] for p in result.dataset.points] == [1, 2]
    assert all(p.extra["var.gre"] == 0.2 for p in result.dataset.points)
    assert "BO=-10 dB" in result.dataset.metadata["selection"]
    for value in (-9.95, float("nan"), float("inf")):
        with pytest.raises(ValueError):
            read_alps_lines(
                text.splitlines(), "sample.mdf", plane="dut", block_index=1, backoff_db=value
            )


def test_backoff_contours_are_explicit_and_do_not_weaken_fixed_pin_checks() -> None:
    texts = [
        block(),
        block(ROW.replace(".2 .3", ".4 .3").replace("20 40", "21 41")),
        block(ROW.replace(".2 .3", ".2 .5").replace("20 40", "22 42")),
    ]
    data = read_alps_lines(
        "".join(texts).splitlines(), "sample.mdf", plane="dut", block_index=1, backoff_db=-10
    ).dataset
    assert len(sweep_choices(data)) == 1
    assert "not a fixed-Pin sweep" in sweep_choices(data)["sweep-0"]
    assert "loadpull-contour" in str(loadpull_panel(data, "sweep-0", "pout_dbm", True))
    assert loadpull_contours(data.points, "pout_dbm", (41.0,), backoff_db=-10)
    with pytest.raises(ValueError, match="input-power"):
        loadpull_contours(data.points, "pout_dbm", (41.0,))
    with pytest.raises(ValueError, match="source BO"):
        loadpull_contours(data.points, "pout_dbm", (41.0,), backoff_db=-9.9)


def test_file_service_streams_without_read_text(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = tmp_path / "sample.mdf"
    source.write_text(block(), encoding="utf-8")

    def forbidden(*args: object, **kwargs: object) -> str:
        raise AssertionError("Whole-file read is not permitted")

    monkeypatch.setattr(Path, "read_text", forbidden)
    assert read_alps_mdf(source, source.name, plane="dut", block_index=1).total_rows == 1


@pytest.mark.parametrize(
    "text,match",
    [
        (block().replace("\nEND\n", "\n"), "Unclosed"),
        (block().replace("BEGIN Sweep", "BEGIN Sweep\nBEGIN Sweep"), "nested"),
        (block().replace("BEGIN Sweep", "END\nBEGIN Sweep"), "unexpected"),
        (block(header=HEADER.replace("Eff_col(real)", "Unknown(real)")), "missing"),
        (block(header=HEADER.replace("BO(real)", "Freq(real)")), "duplicate"),
        (block(row=ROW.replace('"test path/file ""x"" name"', "unquoted")), "quoted"),
        (block(row=ROW.replace('"test path/file ""x"" name"', '"unterminated')), "quoted"),
        (block(row=ROW.replace("20 40", "bad 40")), "invalid numeric"),
        (block(row=ROW.replace("20 40", "20 1e400")), "nonfinite"),
        (block(row=ROW.replace("20 40", "20 40000")), "numeric range"),
        (
            block(
                header=HEADER.replace("BO(real)", "BO(integer)"), row=ROW.replace("-10", "-10.5")
            ),
            "noninteger",
        ),
        ("!preamble\nBEGIN Sweep\n" + HEADER + "\nEND", "empty"),
    ],
)
def test_malformed_streams_rejected(text: str, match: str) -> None:
    with pytest.raises(ValueError, match=match):
        parse(text)


@pytest.mark.parametrize("index", [0, -1, 2])
def test_block_selection_must_exist(index: int) -> None:
    with pytest.raises(ValueError):
        parse(block(), index)


def test_bounds_are_enforced_without_truncation(monkeypatch: pytest.MonkeyPatch) -> None:
    for constant, limit, text, message in (
        ("MAX_ALPS_ROWS", 1, block() + block(), "measurement rows"),
        ("MAX_ALPS_BLOCKS", 1, block() + block(), "blocks"),
        ("MAX_ALPS_BYTES", 10, block(), "file"),
        ("MAX_ALPS_BLOCK_ROWS", 1, block(ROW + "\n" + ROW), "no rows dropped"),
    ):
        with monkeypatch.context() as context:
            context.setattr(alps_mdf, constant, limit)
            with pytest.raises(ValueError, match=message):
                parse(text)


@pytest.mark.parametrize("frequency,blocks,rows", [("1.750", 500, 117000), ("1.800", 456, 97584)])
def test_repository_alps_stream_and_every_selected_measurement(
    frequency: str,
    blocks: int,
    rows: int,
) -> None:
    root = Path(__file__).resolve().parents[2]
    source = next(
        (root / "PA design App" / "data" / "sample-files").glob(f"*{frequency}GHz.tdp.mdf")
    )
    result = read_alps_mdf(source, source.name, plane="dut", block_index=1)
    assert len(result.blocks) == blocks
    assert result.total_rows == rows
    assert sum(block.rows for block in result.blocks) == rows
    with source.open(encoding="utf-8-sig") as stream:
        for line in stream:
            if line.lstrip().startswith("%"):
                names = [token.split("(")[0].lower() for token in line.lstrip("% ").split()]
                break
        measured = []
        for line in stream:
            if line.strip() == "END":
                break
            if line.strip():
                measured.append(
                    dict(
                        zip(
                            names,
                            next(csv.reader([line], delimiter=" ", skipinitialspace=True)),
                            strict=True,
                        )
                    )
                )
    assert len(result.dataset.points) == len(measured)
    for point, raw in zip(result.dataset.points, measured, strict=True):
        assert point.pout_dbm == float(raw["pout_dbm"])
        assert point.pin_dbm == float(raw["pin_avail_dbm"])
        assert point.gain_db == float(raw["gt_db"])
        assert point.gl_r == float(raw["glre"])
        assert point.gl_i == float(raw["glim"])
        assert point.freq_ghz == float(raw["freq"]) == float(frequency)
        assert point.vdc_v == float(raw["vout_v"])
        assert point.idc_a == float(raw["iout_ma"]) / 1000
        assert point.pdc_w == pytest.approx(float(raw["vout_v"]) * float(raw["iout_ma"]) / 1000)
        assert point.source_strings["fname"] == raw["fname"]
        assert math.isfinite(point.pdc_w or 0)
