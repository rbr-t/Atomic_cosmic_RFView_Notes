import csv
from io import StringIO
from pathlib import Path

import pytest

from rfview.domain.network_parameters import s_to_abcd, s_to_h, s_to_t, s_to_y, s_to_z
from rfview.domain.touchstone import (
    parse_touchstone,
    serialize_converted_parameters,
    serialize_touchstone,
)
from rfview.services import read_touchstone


@pytest.mark.parametrize("fixture", ["reference_ri.s2p", "reference_db.s2p", "reference_ma.s1p"])
def test_export_roundtrip_preserves_source_complex_data(fixture: str) -> None:
    source = read_touchstone(Path(__file__).parent / "fixtures" / "touchstone" / fixture)
    before = source.model_dump()
    text = serialize_touchstone(source)
    result = parse_touchstone(text, f"export.s{source.nports}p")
    assert result.freq_ghz == source.freq_ghz
    assert result.z0 == source.z0
    assert result.data_format == "ri"
    assert [(p.param, p.real, p.imag) for p in result.points] == [
        (p.param, p.real, p.imag) for p in source.points
    ]
    assert source.model_dump() == before


def test_export_rejects_incomplete_reordered_and_nonfinite_data() -> None:
    source = parse_touchstone("# GHz S RI R 75\n1 0 0 2 0 0.1 0 0 0", "test.s2p")
    for broken in (
        source.model_copy(update={"points": source.points[:3]}),
        source.model_copy(update={"points": tuple(reversed(source.points))}),
        source.model_copy(update={"z0": float("inf")}),
        source.model_copy(update={"nports": 10}),
    ):
        with pytest.raises(ValueError):
            serialize_touchstone(broken)


@pytest.mark.parametrize(
    "family,convert,units",
    [
        ("Z", s_to_z, ["ohm"] * 4),
        ("Y", s_to_y, ["S"] * 4),
        ("h", s_to_h, ["ohm", "dimensionless", "dimensionless", "S"]),
        ("ABCD", s_to_abcd, ["dimensionless", "ohm", "S", "dimensionless"]),
        ("T", lambda matrix, z0: s_to_t(matrix), ["dimensionless"] * 4),
    ],
)
def test_converted_csv_matches_qualified_matrix_values(family, convert, units) -> None:
    data = parse_touchstone(
        "# GHz S RI R 75\n1 0.1 -0.2 2 0.3 0.02 -0.01 -0.1 0.1\n"
        "2 0.2 -0.1 1 0.2 0.01 0.01 -0.2 0.2",
        "source.s2p",
    )
    before = data.model_dump()
    rows = list(csv.DictReader(StringIO(serialize_converted_parameters(data, family))))
    assert len(rows) == 8
    for offset in range(2):
        record = {
            p.param: complex(p.real, p.imag) for p in data.points[offset * 4 : offset * 4 + 4]
        }
        expected = convert(((record["S11"], record["S12"]), (record["S21"], record["S22"])), 75)
        for index, row in enumerate(rows[offset * 4 : offset * 4 + 4]):
            assert row["unit"] == units[index]
            assert row["representation"] == family
            assert float(row["frequency_ghz"]) == data.freq_ghz[offset]
            assert float(row["source_z0_port1_ohm"]) == 75
            assert float(row["source_z0_port2_ohm"]) == 75
            assert (
                complex(float(row["real"]), float(row["imag"])) == expected[index // 2][index % 2]
            )
    assert data.model_dump() == before


def test_converted_export_has_no_partial_singular_results() -> None:
    data = parse_touchstone(
        "# GHz S RI R 50\n1 0 0 0.1 0 0.1 0 0 0\n2 1 0 0 0 0 0 0 0", "singular.s2p"
    )
    with pytest.raises(ValueError, match="failed at 2 GHz"):
        serialize_converted_parameters(data, "Z")
    for family in ("S", "Stability", "invalid"):
        with pytest.raises(ValueError, match="requires"):
            serialize_converted_parameters(data, family)
