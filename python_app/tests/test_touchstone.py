import hashlib
import json
from pathlib import Path
from typing import Any

import pytest

from rfview.domain.touchstone import MAX_TOUCHSTONE_BYTES, parse_touchstone
from rfview.services import read_touchstone

FIXTURES = Path(__file__).parent / "fixtures"
REFERENCE = json.loads((FIXTURES / "touchstone_reference.json").read_text(encoding="utf-8"))


def equivalent(actual: Any, expected: Any) -> None:
    if isinstance(expected, dict):
        for key, value in expected.items():
            equivalent(actual[key], value)
    elif isinstance(expected, list):
        assert len(actual) == len(expected)
        for left, right in zip(actual, expected, strict=True):
            equivalent(left, right)
    elif isinstance(expected, str):
        assert actual == expected
    else:
        assert actual == pytest.approx(expected, rel=1e-10, abs=1e-12)


@pytest.mark.parametrize("case", REFERENCE["cases"], ids=lambda case: case["filename"])
def test_file_parity_with_r(case: dict[str, Any]) -> None:
    path = FIXTURES / "touchstone" / case["filename"]
    assert hashlib.md5(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() == case["md5"]
    result = read_touchstone(path)
    equivalent(result.model_dump(mode="json"), case["expected"])
    result.model_dump_json()


@pytest.mark.parametrize("unit,frequency", [("Hz", 1e9), ("kHz", 1e6), ("MHz", 1e3), ("GHz", 1)])
def test_frequency_units(unit: str, frequency: float) -> None:
    result = parse_touchstone(f"# {unit} S RI R 50\n{frequency} 0.2 0.3", "a.s1p")
    assert result.freq_ghz == (1,)


def test_ordering_and_wrapped_records() -> None:
    result = read_touchstone(FIXTURES / "touchstone" / "reference_ri.s2p")
    assert [point.param for point in result.points[:4]] == ["S11", "S21", "S12", "S22"]
    assert result.points[1].real == 2
    assert result.points[2].real == 0.03
    assert len(result.points) == 8
    assert result.comments[0].startswith("! Synthetic")


def test_defaults_bom_exponents_and_tag() -> None:
    result = parse_touchstone("\ufeff! comment\n1D0 0.5 0", r"C:\data\default.S1P", "chosen")
    assert result.filename == "default.S1P"
    assert result.freq_unit == "ghz"
    assert result.data_format == "ma"
    assert result.z0 == 50
    assert result.points[0].dataset_tag == "chosen"
    assert result.points[0].real == 0.5


@pytest.mark.parametrize(
    "text",
    [
        "",
        "! no data",
        "1 0.1",
        "1 0.1 0 9",
        "1 0.1 BAD",
        "1 NaN 0",
        "1 inf 0",
        "-1 0.1 0",
        "1 0.1 0\n1 0.2 0",
        "2 0.1 0\n1 0.2 0",
        "# GHz Y RI R 50\n1 0.1 0",
        "# GHz S WHAT R 50\n1 0.1 0",
        "# THz S RI R 50\n1 0.1 0",
        "# GHz S RI R 0\n1 0.1 0",
        "# GHz S RI R NaN\n1 0.1 0",
        "# GHz S RI R invalid\n1 0.1 0",
        "# GHz S RI R\n1 0.1 0",
        "# GHz S RI R 50 75\n1 0.1 0",
        "# GHz S RI R 50\n# GHz S RI R 50\n1 0.1 0",
        "1 0.1 0\n# GHz S RI R 50",
        "[Version] 2.0\n# GHz S RI R 50\n1 0.1 0",
        "# GHz S MA R 50\n1 -0.1 0",
        "# GHz S DB R 50\n1 100000 0",
    ],
)
def test_invalid_data_never_silently_truncated(text: str) -> None:
    with pytest.raises(ValueError):
        parse_touchstone(text, "bad.s1p")


@pytest.mark.parametrize("filename", ["bad.s0p", "bad.s10p", "bad.ts", "bad.snp", "bad.csv"])
def test_unsupported_formats_are_explicit(filename: str) -> None:
    with pytest.raises(ValueError, match="s1p through .s9p"):
        parse_touchstone("1 0.1 0", filename)


def test_size_and_record_limits() -> None:
    with pytest.raises(ValueError, match="5 MiB"):
        parse_touchstone("!" * (MAX_TOUCHSTONE_BYTES + 1), "big.s1p")
    with pytest.raises(ValueError, match="frequency records"):
        parse_touchstone("1 0 0\n" * 100_001, "big.s1p")
    with pytest.raises(ValueError, match="tag"):
        parse_touchstone("1 0.1 0", "a.s1p", " ")


def test_missing_file_raises(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError):
        read_touchstone(tmp_path / "missing.s1p")


def test_parser_oracle_source_revision() -> None:
    source = (
        Path(__file__).resolve().parents[2]
        / "PA design App"
        / "src"
        / "modules"
        / "rf_tools"
        / "sp_parsers.R"
    )
    assert (
        hashlib.md5(source.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        == (REFERENCE["provenance"]["source_md5"])
    )
