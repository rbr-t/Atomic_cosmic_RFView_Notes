from pathlib import Path

import pytest

from rfview.domain.touchstone import parse_touchstone, serialize_touchstone
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
        source.model_copy(update={"nports": 3}),
    ):
        with pytest.raises(ValueError):
            serialize_touchstone(broken)
