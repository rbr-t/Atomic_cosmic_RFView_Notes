import math

import pytest

from rfview.domain.touchstone import (
    converted_parameters,
    parse_touchstone,
    serialize_touchstone,
    transform_network_basis,
)


def network(nports, values, references=None, modes=()):
    return parse_touchstone(
        "[Version] 2.0\n# GHz S RI R 50\n"
        f"[Number of Ports] {nports}\n[Number of Frequencies] 1\n"
        + ("[Two-Port Data Order] 21_12\n" if nports == 2 else "")
        + ("[Reference] " + " ".join(str(v) for v in references) + "\n" if references else "")
        + ("[Mixed-Mode Order] " + " ".join(modes) + "\n" if modes else "")
        + "[Network Data]\n1 "
        + " ".join(f"{v.real} {v.imag}" for v in values)
        + "\n[End]\n",
        "source.ts",
    )


def test_independent_two_port_through_becomes_differential_minus_common_plus() -> None:
    source = network(2, [0j, 1 + 0j, 1 + 0j, 0j])
    mixed = transform_network_basis(source, ("D1,2", "C1,2"))
    values = {p.param: complex(p.real, p.imag) for p in mixed.points}
    assert values["S11"] == pytest.approx(-1)
    assert values["S22"] == pytest.approx(1)
    assert values["S12"] == pytest.approx(0)
    assert values["S21"] == pytest.approx(0)
    assert mixed.port_references() == (100, 25)
    assert source.mixed_mode_order == ()
    with pytest.raises(ValueError, match="Mixed-mode"):
        converted_parameters(mixed, "Z")
    restored = transform_network_basis(mixed)
    assert restored.mixed_mode_order == ()
    assert len(converted_parameters(restored, "T")) == 4


@pytest.mark.parametrize(
    "nports,modes,references",
    [
        (2, ("C2,1", "D2,1"), (75, 75)),
        (3, ("D1,2", "S3", "C1,2"), (50, 50, 75)),
        (4, ("D2,1", "D3,4", "C2,1", "C3,4"), (50, 50, 75, 75)),
        (
            9,
            ("S9", "D1,2", "C1,2", "D4,3", "C4,3", "S5", "S6", "S7", "S8"),
            (50, 50, 75, 75, 25, 30, 35, 40, 45),
        ),
    ],
)
def test_roundtrip_complex_nonreciprocal_matrices_preserves_power_norm(
    nports, modes, references
) -> None:
    values = [complex((i + 1) / 100, -(i + 2) / 200) for i in range(nports**2)]
    original = network(nports, values, references)
    before = original.model_dump_json()
    mixed = transform_network_basis(original, modes)
    assert math.fsum(p.mag_linear**2 for p in mixed.points) == pytest.approx(
        math.fsum(p.mag_linear**2 for p in original.points)
    )
    restored = transform_network_basis(mixed)
    assert restored.reference_ohms == references
    for a, b in zip(restored.points, original.points, strict=True):
        assert a.param == b.param
        assert complex(a.real, a.imag) == pytest.approx(complex(b.real, b.imag), abs=1e-14)
    assert original.model_dump_json() == before
    exported = parse_touchstone(serialize_touchstone(mixed), "mixed.ts")
    assert exported.mixed_mode_order == modes
    assert exported.reference_ohms == references


def test_mode_permutation_and_orientation_are_not_silently_ignored() -> None:
    source = network(3, [complex(i / 10, 0.05) for i in range(9)], (50, 50, 75))
    first = transform_network_basis(source, ("D1,2", "C1,2", "S3"))
    changed = transform_network_basis(first, ("C2,1", "S3", "D2,1"))
    direct = transform_network_basis(source, ("C2,1", "S3", "D2,1"))
    for a, b in zip(changed.points, direct.points, strict=True):
        assert complex(a.real, a.imag) == pytest.approx(complex(b.real, b.imag), abs=1e-14)


def test_unequal_pair_references_and_noise_transforms_fail_explicitly() -> None:
    source = network(2, [complex(0.1)] * 4, (50, 75))
    with pytest.raises(ValueError, match="equal single-ended"):
        transform_network_basis(source, ("D1,2", "C1,2"))
    noisy = parse_touchstone("# GHz S RI R 50\n1 0 0 2 0 .01 0 0 0\n.5 1 .3 0 .2", "noise.s2p")
    with pytest.raises(ValueError, match="Noise-parameter"):
        transform_network_basis(noisy, ("D1,2", "C1,2"))
