import math

from rfview.domain.models import finite, nonnegative, positive
from rfview.domain.power import dbm_to_watts, watts_to_dbm


def power_from_watts(watt: float) -> dict[str, float]:
    return {"watt": watt, "dbm": watts_to_dbm(watt), "dbw": watts_to_dbm(watt) - 30}


def power_from_dbm(dbm: float) -> dict[str, float]:
    return {"dbm": dbm, "watt": dbm_to_watts(dbm), "dbw": dbm - 30}


def power_from_voltage(v: float, z: float = 50) -> dict[str, float]:
    positive(v, "RMS voltage (V)")
    positive(z, "impedance (ohm)")
    power = v**2 / z
    return {
        "voltage_v": v,
        "impedance_ohm": z,
        "power_w": power,
        "power_dbm": watts_to_dbm(power),
        "current_a": v / z,
    }


def wavelengths(freq_ghz: float, er: float = 1) -> dict[str, float]:
    positive(freq_ghz, "frequency (GHz)")
    positive(er, "relative permittivity")
    wavelength = 300 / freq_ghz
    effective = wavelength / math.sqrt(er)
    return {
        "freq_ghz": freq_ghz,
        "freq_mhz": freq_ghz * 1000,
        "er": er,
        "lambda_mm": wavelength,
        "lambda_eff_mm": effective,
        "quarter_wave_mm": effective / 4,
        "half_wave_mm": effective / 2,
    }


def sparams(s11_mag: float, s11_phase: float) -> dict[str, float | None]:
    finite(s11_mag, "S11 magnitude")
    finite(s11_phase, "S11 phase (deg)")
    if not 0 <= s11_mag <= 1:
        raise ValueError("Passive VSWR calculation requires S11 magnitude in [0, 1]")
    phase = math.radians(s11_phase)
    return {
        "s11_mag": s11_mag,
        "s11_phase_deg": s11_phase,
        "gamma_real": s11_mag * math.cos(phase),
        "gamma_imag": s11_mag * math.sin(phase),
        "return_loss_db": -20 * math.log10(s11_mag) if s11_mag else None,
        "vswr": (1 + s11_mag) / (1 - s11_mag) if s11_mag < 1 else None,
    }


def thermal(
    pout_w: float,
    pae_pct: float,
    rth_jc: float = 1.5,
    rth_cs: float = 0.5,
    rth_sa: float = 2,
    ta_c: float = 25,
    tj_max_c: float = 200,
) -> dict[str, float | str]:
    nonnegative(pout_w, "Pout (W)")
    finite(pae_pct, "PAE (%)")
    if not 0 < pae_pct <= 100:
        raise ValueError("PAE must be in (0, 100] %")
    for name, value in (("Rth jc", rth_jc), ("Rth cs", rth_cs), ("Rth sa", rth_sa)):
        nonnegative(value, name)
    finite(ta_c, "ambient temperature")
    finite(tj_max_c, "maximum junction temperature")
    pdc = pout_w / (pae_pct / 100)
    dissipation = pdc - pout_w
    resistance = rth_jc + rth_cs + rth_sa
    tj = ta_c + dissipation * resistance
    margin = tj_max_c - tj
    return {
        "pout_w": pout_w,
        "pae_pct": pae_pct,
        "pdc_w": pdc,
        "pdiss_w": dissipation,
        "rth_jc": rth_jc,
        "rth_cs": rth_cs,
        "rth_sa": rth_sa,
        "rth_total": resistance,
        "ta_c": ta_c,
        "ts_c": ta_c + dissipation * rth_sa,
        "tc_c": ta_c + dissipation * (rth_cs + rth_sa),
        "tj_c": tj,
        "tj_max_c": tj_max_c,
        "margin_c": margin,
        "status": "SAFE" if margin > 20 else "MARGINAL" if margin > 0 else "VIOLATION",
    }
