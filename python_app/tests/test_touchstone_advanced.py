import pytest

from rfview.domain.touchstone import converted_parameters, parse_touchstone, serialize_touchstone
from rfview.touchstone_ui import touchstone_panel


def advanced(
    body: str, *, ports: int = 2, matrix: str = "Full", declarations: str = "", count: int = 1
) -> str:
    return (
        "[Version] 2.0\n# MHz S RI R 50\n"
        f"[Number of Ports] {ports}\n[Number of Frequencies] {count}\n"
        + ("[Two-Port Data Order] 12_21\n" if ports == 2 else "")
        + f"[Matrix Format] {matrix}\n{declarations}\n[Network Data]\n{body}\n[End]\n"
    )


@pytest.mark.parametrize("ports", [1, 2, 3, 4, 9])
@pytest.mark.parametrize("matrix", ["Lower", "Upper"])
def test_triangular_complex_values_mirror_without_conjugation(ports: int, matrix: str) -> None:
    indices = [
        (r, c)
        for r in range(ports)
        for c in range(ports)
        if (c <= r if matrix == "Lower" else c >= r)
    ]
    pairs = {rc: complex(index / 100, -index / 200) for index, rc in enumerate(indices, 1)}
    body = "1000 " + " ".join(f"{v.real} {v.imag}" for v in pairs.values())
    data = parse_touchstone(advanced(body, ports=ports, matrix=matrix), f"triangle.s{ports}p")
    actual = {p.param: complex(p.real, p.imag) for p in data.points}
    for (r, c), expected in pairs.items():
        assert actual[f"S{r + 1}{c + 1}"] == actual[f"S{c + 1}{r + 1}"] == expected
    restored = parse_touchstone(serialize_touchstone(data), "expanded.ts", data.dataset_tag)
    assert restored.points == data.points
    assert "[Matrix Format] Full" in serialize_touchstone(data)


def test_mixed_mode_preserves_order_and_modal_references() -> None:
    data = parse_touchstone(
        advanced(
            "1000 " + " ".join(["0.1 -0.2"] * 9),
            ports=3,
            declarations="[Mixed-Mode Order]\nD1, 2 S3 C1,2\n[Reference] 50 50 75",
        ),
        "mixed.ts",
    )
    assert data.mixed_mode_order == ("D1,2", "S3", "C1,2")
    assert data.port_references() == (100, 75, 25)
    html = str(touchstone_panel(data, "S33", "Smith"))
    assert "25 ohm" in html
    assert "not physical single-ended" in html
    assert (
        data.points
        == parse_touchstone(serialize_touchstone(data), "again.ts", data.dataset_tag).points
    )
    assert (
        parse_touchstone(serialize_touchstone(data), "again.ts").mixed_mode_order
        == data.mixed_mode_order
    )
    for representation in ("Z", "Y", "h", "ABCD", "T", "Stability", "Circles", "PowerGain"):
        with pytest.raises(ValueError, match="Mixed-mode|two-port"):
            touchstone_panel(data, "S11", representation)


@pytest.mark.parametrize(
    "order",
    [
        "D1,2 C2,1 S3",
        "D1,2 S2 S3",
        "D1,2 D1,2 S3",
        "D1,1 C1,1 S3",
        "D1,4 C1,4 S3",
        "D1,2 S3",
        "D1,2 C1,2 Q3",
    ],
)
def test_invalid_mixed_mode_definitions_rejected(order: str) -> None:
    with pytest.raises(ValueError, match="[Mm]ixed"):
        parse_touchstone(
            advanced(
                "1000 " + " ".join(["0.1 0"] * 9),
                ports=3,
                declarations=f"[Mixed-Mode Order] {order}",
            ),
            "bad.ts",
        )


def test_mixed_two_port_does_not_gain_single_ended_conversion() -> None:
    data = parse_touchstone(
        advanced(
            "1000 0.1 0 0.02 0 0.03 0 0.2 0",
            declarations="[Mixed-Mode Order] D1,2 C1,2",
        ),
        "mixed.ts",
    )
    with pytest.raises(ValueError, match="declared basis"):
        converted_parameters(data, "T")
    with pytest.raises(ValueError, match="declared basis"):
        touchstone_panel(data, "S11", "Stability")


def noise_text() -> str:
    return advanced(
        "1000 0.1 0 2 0 0.01 0 0.2 0\n[Noise Data]\n500 1.2 0.3 -45 19\n1500 2.3 0.4 30 22",
        declarations="[Number of Noise Frequencies] 2\n[Reference] 75 25",
    )


def test_noise_units_separate_grid_and_option_reference_roundtrip() -> None:
    data = parse_touchstone(noise_text(), "noise.ts")
    assert [p.freq_ghz for p in data.noise] == [0.5, 1.5]
    assert data.freq_ghz == (1,)
    assert data.noise_reference_ohm == 50  # Not the 75-ohm input port reference.
    assert data.noise[0].resistance_ohm == 19  # TS2 Rn is not normalized.
    html = str(touchstone_panel(data, "S21", "Noise"))
    assert "option-line reference 50 ohm" in html
    assert "Rn (ohm)" in html
    exported = serialize_touchstone(data)
    restored = parse_touchstone(exported, "again.ts")
    assert restored.noise == data.noise
    assert restored.noise_reference_ohm == 50
    assert restored.reference_ohms == (75, 25)


@pytest.mark.parametrize(
    "old,new,match",
    [
        ("[Number of Noise Frequencies] 2", "", "requires Number"),
        ("[Number of Noise Frequencies] 2", "[Number of Noise Frequencies] 1", "row count"),
        ("[Number of Noise Frequencies] 2", "[Number of Noise Frequencies] -1", "positive"),
        ("[Number of Noise Frequencies] 2", "[Number of Noise Frequencies] bad", "count"),
        ("1500 2.3 0.4 30 22", "500 2.3 0.4 30 22", "increasing"),
        ("500 1.2 0.3 -45 19", "1100 1.2 0.3 -45 19", "highest network"),
        ("500 1.2 0.3 -45 19", "500 1.2 -0.3 -45 19", "greater than"),
        ("500 1.2 0.3 -45 19", "500 nan 0.3 -45 19", "finite"),
        ("500 1.2 0.3 -45 19", "500 1.2 0.3 -45", "five finite"),
        ("[Noise Data]", "[Noise Data] arg", "no argument"),
    ],
)
def test_invalid_noise_rejected(old: str, new: str, match: str) -> None:
    with pytest.raises(ValueError, match=match):
        parse_touchstone(noise_text().replace(old, new), "bad.ts")


def test_missing_noise_section_and_triangular_width_rejected() -> None:
    with pytest.raises(ValueError, match="row count"):
        parse_touchstone(
            advanced(
                "1000 0.1 0 2 0 0.01 0 0.2 0",
                declarations="[Number of Noise Frequencies] 1",
            ),
            "bad.ts",
        )
    with pytest.raises(ValueError, match="count/width"):
        parse_touchstone(advanced("1000 0.1 0", matrix="Lower"), "bad.ts")
