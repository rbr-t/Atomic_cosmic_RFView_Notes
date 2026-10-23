import math

import pytest

from rfview.domain.reliability import LifetimeInputs, lifetime_estimate, reliability_curve
from rfview.domain.stability import power_gain_estimates, stability_metrics
from rfview.domain.touchstone import parse_touchstone
from rfview.touchstone_ui import touchstone_panel


def test_conventional_power_gain_uses_ten_log_without_altering_legacy() -> None:
    s = ((0, 0.1), (2, 0))
    legacy = stability_metrics(s)
    result = power_gain_estimates(s)
    assert result.msg_db == pytest.approx(10 * math.log10(20))
    assert result.mag_db == pytest.approx(10 * math.log10(4))
    assert legacy.msg_db == pytest.approx(2 * result.msg_db)
    assert legacy.mag_db == pytest.approx(2 * result.mag_db)
    assert result.model_version == "conventional-power-gain-v2"
    assert result.warnings


def test_power_gain_undefined_and_stable_region_requirements() -> None:
    assert power_gain_estimates(((0, 0), (2, 0))).msg_db is None
    assert power_gain_estimates(((0, 0.1), (0, 0))).msg_db is None
    assert power_gain_estimates(((0.8, 0.5), (3, 0.8))).mag_db is None
    assert power_gain_estimates(((2, 0.1), (2, 2))).mag_db is None
    result = power_gain_estimates(((0.1, 1e-10), (1, 0.2)))
    assert result.mag_db is not None
    result.model_dump_json()


def test_new_power_gain_view_is_explicit_and_legacy_table_unchanged() -> None:
    data = parse_touchstone("# GHz S RI R 50\n1 0 0 2 0 0.1 0 0 0", "gain.s2p")
    html = str(touchstone_panel(data, "S21", "PowerGain"))
    assert "conventional-power-gain-v2" in html
    assert "13.0102999566" in html
    assert "10*log10" in html
    legacy = str(touchstone_panel(data, "S21", "Stability"))
    assert "26.0205999133" in legacy
    assert "legacy-r-stability-v1" in legacy


def test_reference_lifetime_and_thermal_acceleration_direction() -> None:
    reference = lifetime_estimate(LifetimeInputs(tj_c=125))
    hot = lifetime_estimate(LifetimeInputs(tj_c=150))
    cold = lifetime_estimate(LifetimeInputs(tj_c=100))
    assert reference.mttf_hours == pytest.approx(1e6)
    assert hot.mttf_hours < reference.mttf_hours < cold.mttf_hours
    assert hot.failure_rate_per_hour > reference.failure_rate_per_hour
    expected = 1e6 * math.exp((0.7 / 8.617e-5) * (1 / (150 + 273.15) - 1 / (125 + 273.15)))
    assert hot.mttf_hours == pytest.approx(expected, rel=1e-12)
    stressed = lifetime_estimate(LifetimeInputs(tj_c=125, voltage_stress=2, current_stress=2))
    assert stressed.mttf_hours == pytest.approx(1e6 / 16)
    assert reference.warnings


@pytest.mark.parametrize(
    "values",
    [
        {"tj_c": -273.15},
        {"tj_c": float("nan")},
        {"tj_c": True},
        {"tj_c": 125, "base_hours": 0},
        {"tj_c": 125, "activation_ev": -1},
        {"tj_c": 125, "voltage_stress": 0},
        {"tj_c": 125, "current_stress": -1},
        {"tj_c": 125, "reference_c": -274},
    ],
)
def test_invalid_lifetime_inputs_rejected(values: dict) -> None:
    with pytest.raises(ValueError):
        lifetime_estimate(LifetimeInputs.model_validate(values))


def test_lifetime_numeric_range_explicit_and_reliability_shape() -> None:
    with pytest.raises(ValueError, match="numeric range"):
        lifetime_estimate(LifetimeInputs(tj_c=1e6, reference_c=-273, activation_ev=10))
    curve = reliability_curve([0, 1e6, 2e6], 1e6)
    assert curve[0] == (0, 100)
    assert curve[1][1] == pytest.approx(100 / math.e)
    assert curve[2][1] < curve[1][1]
    for times, hours in (
        ([], 1),
        ([0, -1], 1),
        ([0, 0], 1),
        ([float("inf")], 1),
        ([True], 1),
        ([0], 0),
    ):
        with pytest.raises(ValueError):
            reliability_curve(times, hours)
