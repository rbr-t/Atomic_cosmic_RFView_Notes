import pytest

from rfview.domain.touchstone import parse_touchstone, serialize_touchstone
from rfview.touchstone_ui import touchstone_panel

NETWORK = "# MHz S RI R 75\n1000 .1 -.2 2 .3 .01 -.02 .2 -.1\n2000 .2 -.1 1 .4 .02 -.01 .1 -.2\n"


def test_v1_noise_has_independent_grid_normalized_resistance_and_ma_gamma() -> None:
    data = parse_touchstone(NETWORK + "500 1.2 .3 -45 .2\n2500 2 .4 30 .3", "noise.s2p")
    assert data.freq_ghz == (1, 2)
    assert len(data.points) == 8 and len(data.noise) == 2
    assert data.noise_reference_ohm == 75
    assert data.noise[0].freq_ghz == 0.5
    assert data.noise[1].freq_ghz == 2.5
    assert data.noise[0].gamma_opt_mag == 0.3
    assert data.noise[0].gamma_opt_deg == -45
    assert data.noise[0].resistance_ohm == 15
    assert data.noise[1].resistance_ohm == 22.5
    exported = serialize_touchstone(data)
    assert "[Version] 2.0" in exported
    restored = parse_touchstone(exported, "noise.ts")
    assert restored.noise == data.noise and restored.points == data.points
    assert "15" in str(touchstone_panel(data, "S11", "Noise"))


def test_wrapped_network_and_equal_frequency_noise_boundary() -> None:
    text = "# GHz S MA R 50\n1 .1 0 2 0\n.01 0 .2 0\n1 1 .25 90 .1"
    data = parse_touchstone(text, "wrapped.s2p")
    assert len(data.points) == 4
    assert data.noise[0].resistance_ohm == 5
    assert data.noise[0].freq_ghz == 1


@pytest.mark.parametrize(
    "tail,match",
    [
        ("500 1 .3 45 -.1", "greater than or equal"),
        ("500 1 -.3 45 .1", "greater than or equal"),
        ("500 nan .3 45 .1", "finite"),
        ("500 1 .3 45 .1\n400 1 .3 45 .1", "strictly increasing"),
        ("500 1 .3 45 .1\n1000 .1 0 2 0 .01 0 .2 0", "five finite"),
        ("500 1 .3 45 .1\n600 1 .3 45", "five finite"),
        ("-500 1 .3 45 .1", "greater than or equal"),
        ("2500 1 .3 45 .1", "Incomplete"),
        ("500 1 .3 45 1e308", "numeric range"),
    ],
)
def test_malformed_noise_is_not_network_data_or_silently_dropped(tail, match) -> None:
    with pytest.raises(ValueError, match=match):
        parse_touchstone(NETWORK + tail, "bad.s2p")


def test_network_frequency_errors_and_non_two_port_noise_remain_rejected() -> None:
    with pytest.raises(ValueError, match="strictly increasing"):
        parse_touchstone(NETWORK + "1000 .1 0 2 0 .01 0 .2 0", "bad.s2p")
    with pytest.raises(ValueError, match="Incomplete"):
        parse_touchstone("# GHz S RI R 50\n1 0 0\n.5 1 .3 0 .1", "bad.s1p")
    with pytest.raises(ValueError, match="Incomplete"):
        parse_touchstone("# GHz S RI R 50\n1 .1 0 2 0\n.5 1 .3 0 .1", "bad.s2p")
