import pytest

from rfview.domain.touchstone import parse_touchstone, serialize_touchstone
from rfview.touchstone_ui import touchstone_panel


def v2(ports: int = 2, order: str = "21_12", refs: str = "50 75") -> str:
    values = " ".join(f"{index / 100:g} {-index / 200:g}" for index in range(1, ports**2 + 1))
    return (
        "[Version] 2.0\n# GHz S RI R 50\n"
        f"[Number of Ports] {ports}\n[Number of Frequencies] 1\n"
        f"[Reference] {refs}\n[Matrix Format] Full\n"
        + (f"[Two-Port Data Order] {order}\n" if ports == 2 else "")
        + f"[Network Data]\n1 {values}\n[End]\n"
    )


@pytest.mark.parametrize("ports", [1, 2, 3, 4, 9])
@pytest.mark.parametrize("version", ["1.0", "2.0"])
def test_matrix_order_and_exact_roundtrip(ports: int, version: str) -> None:
    text = v2(ports, refs=" ".join(str(50 + i) for i in range(ports)))
    if version == "1.0":
        text = "# GHz S RI R 50\n" + text.split("[Network Data]\n")[1].split("[End]")[0]
    source = parse_touchstone(text, f"original.s{ports}p")
    assert source.nports == ports
    expected = (
        ["S11", "S21", "S12", "S22"]
        if ports == 2
        else [f"S{r}{c}" for r in range(1, ports + 1) for c in range(1, ports + 1)]
    )
    assert [p.param for p in source.points] == expected
    for index, point in enumerate(source.points, 1):
        assert point.real == pytest.approx(index / 100)
        assert point.imag == pytest.approx(-index / 200)
    exported = serialize_touchstone(source)
    restored = parse_touchstone(exported, f"restored.s{ports}p", source.dataset_tag)
    assert restored.points == source.points  # dataset tag is part of every point
    assert restored.version == version
    assert restored.reference_ohms == source.reference_ohms


def test_two_port_order_12_21_is_reordered_without_transposition_errors() -> None:
    data = parse_touchstone(v2(order="12_21"), "reference.ts")
    assert [(p.param, p.real) for p in data.points] == [
        ("S11", 0.01),
        ("S21", 0.03),
        ("S12", 0.02),
        ("S22", 0.04),
    ]
    restored = parse_touchstone(serialize_touchstone(data), "reference.ts")
    assert restored.points == data.points
    assert restored.reference_ohms == (50, 75)
    assert "Per-port reference impedances" in str(touchstone_panel(data, "S21"))
    for representation in ("Z", "Y", "h", "ABCD"):
        with pytest.raises(ValueError, match="not silently renormalized"):
            touchstone_panel(data, "S21", representation)
    assert "T21 real" in str(touchstone_panel(data, "S21", "T"))


def test_multiport_smith_and_two_port_only_boundaries() -> None:
    data = parse_touchstone(v2(3, refs="50 60 70"), "three.ts")
    assert "S33 impedance Smith chart" in str(touchstone_panel(data, "S33", "Smith"))
    assert "70 ohm" in str(touchstone_panel(data, "S33", "Smith"))
    assert "S32 magnitude" in str(touchstone_panel(data, "S32"))
    for representation in ("Z", "Y", "h", "ABCD", "T", "Stability", "Circles", "PowerGain"):
        with pytest.raises(ValueError, match="two-port"):
            touchstone_panel(data, "S33", representation)


def test_reference_continuations_comments_case_defaults_and_bom() -> None:
    text = v2().replace("[Reference] 50 75", "[reference] 50 ! port one\n75")
    text = "\ufeff! a comment\n" + text.replace("[Matrix Format] Full\n", "")
    data = parse_touchstone(text, "wrapped.ts")
    assert data.reference_ohms == (50, 75)
    assert data.comments == ("! a comment",)
    without_refs = v2().replace("[Reference] 50 75\n", "")
    assert parse_touchstone(without_refs, "default.ts").reference_ohms == (50, 50)


@pytest.mark.parametrize(
    "original,replacement,match",
    [
        ("[Version] 2.0", "[Version] 2.1", "must start"),
        ("[Number of Ports] 2", "[Number of Ports] 3", "port count"),
        ("[Number of Frequencies] 1", "[Number of Frequencies] 2", "frequency count"),
        ("[Number of Frequencies] 1", "[Number of Frequencies] bad", "integer"),
        ("[Reference] 50 75", "[Reference] 50", "one positive"),
        ("[Reference] 50 75", "[Reference] 0 75", "one positive"),
        ("[Reference] 50 75", "[Reference] inf 75", "one positive"),
        ("[Matrix Format] Full", "[Matrix Format] Lower", "triangular"),
        ("[Matrix Format] Full", "[Mixed-Mode Order] D1,2 C1,2", "Unsupported"),
        ("[Matrix Format] Full", "[Number of Noise Frequencies] 1", "noise"),
        ("[Matrix Format] Full", "[Begin Information]", "Unsupported"),
        ("[Two-Port Data Order] 21_12", "[Two-Port Data Order] other", "data order"),
        ("[Two-Port Data Order] 21_12", "", "requires.*Two-Port Data Order"),
        ("[End]", "", "requires"),
        ("[End]", "[End]\n1 0 0", "follows"),
        ("[Network Data]", "[Network Data] extra", "no argument"),
        ("[Network Data]", "[Noise Data]", "Unsupported"),
        ("[Reference] 50 75", "[Reference] 50 75\n[Reference] 50 75", "Duplicate"),
        ("[Network Data]", "# GHz S RI R 50\n[Network Data]", "Duplicate"),
    ],
)
def test_unsupported_or_inconsistent_v2_is_rejected(
    original: str, replacement: str, match: str
) -> None:
    with pytest.raises(ValueError, match=match):
        parse_touchstone(v2().replace(original, replacement), "invalid.s2p")
