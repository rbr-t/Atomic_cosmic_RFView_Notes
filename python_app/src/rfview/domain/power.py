import math
from collections.abc import Iterable

from rfview.domain.models import finite, positive


def dbm_to_watts(dbm: float) -> float:
    finite(dbm, "power (dBm)")
    try:
        return positive(10 ** (dbm / 10) / 1000, "power (W)")
    except OverflowError as exc:
        raise ValueError("Power is outside the supported numeric range") from exc


def watts_to_dbm(watts: float) -> float:
    return 10 * math.log10(positive(watts, "power (W)") * 1000)


def sum_dbm(values: Iterable[float]) -> float:
    powers = list(values)
    if not powers:
        raise ValueError("At least one power is required")
    peak = max(powers)
    for power in powers:
        finite(power, "power (dBm)")
    return peak + 10 * math.log10(math.fsum(10 ** ((power - peak) / 10) for power in powers))
