import math

from rfview.domain.models import finite, nonnegative, positive


def atmospheric_loss(freq_ghz: float) -> float:
    nonnegative(freq_ghz, "frequency (GHz)")
    return (
        0.01 * freq_ghz
        + 15 * math.exp(-((freq_ghz - 60) ** 2) / 50)
        + 8 * math.exp(-((freq_ghz - 22) ** 2) / 18)
    )


def efficiency(freq_ghz: float, technology: str) -> float:
    nonnegative(freq_ghz, "frequency (GHz)")
    parameters = {"LDMOS": (65, 0.8, 5), "GaN": (70, 0.3, 20), "SiGe": (50, 0.15, 10)}
    if technology not in parameters:
        raise ValueError(f"Unsupported efficiency technology: {technology}")
    intercept, slope, floor = parameters[technology]
    return max(intercept - slope * freq_ghz, floor)


def recommend_technology(freq_ghz: float) -> dict[str, str]:
    positive(freq_ghz, "frequency (GHz)")
    if freq_ghz < 4:
        values = ("LDMOS", "20-40 GHz", "15-18 dB", "primary")
    elif freq_ghz < 12:
        values = ("GaN_SiC", "30-100 GHz", "12-15 dB", "success")
    elif freq_ghz < 40:
        values = ("GaN_SiC", "50-100 GHz", "10-12 dB", "success")
    elif freq_ghz < 100:
        values = ("SiGe", "200-300 GHz", "8-10 dB", "warning")
    else:
        values = ("InP", "300-600 GHz", "6-8 dB", "danger")
    return dict(zip(("tech", "fT_range", "expected_gain", "color"), values, strict=True))


def passive_loss(component_type: str, freq_ghz: float) -> float:
    nonnegative(freq_ghz, "frequency (GHz)")
    match component_type:
        case "transmission_line":
            return 0.05 + 0.15 * math.sqrt(freq_ghz) + 0.02 * freq_ghz
        case "wilkinson_splitter" | "wilkinson_combiner":
            return 3.1 + 0.05 * freq_ghz
        case "quadrature_hybrid":
            return 0.3 + 0.08 * freq_ghz + 0.02 * math.pow(freq_ghz, 1.5)
        case "t_junction":
            return 0.05 + 0.03 * freq_ghz
        case "doherty_combiner":
            return 0.2 + 0.02 * freq_ghz + 0.01 * math.pow(freq_ghz, 1.3)
        case "transformer":
            if freq_ghz < 0.5:
                return 0.3 + 0.05 * freq_ghz
            if freq_ghz < 3:
                return 0.2 + 0.03 * (freq_ghz - 0.5)
            return 0.4 + 0.1 * (freq_ghz - 3)
        case _:
            raise ValueError(f"Unsupported passive loss model: {component_type}")


def link_budget(
    tx_power_dbm: float,
    tx_gain_dbi: float,
    rx_gain_dbi: float,
    distance_km: float,
    freq_ghz: float,
    bw_mhz: float,
    noise_figure_db: float,
    snr_req_db: float,
) -> dict[str, float | str]:
    for name, value in (
        ("TX power", tx_power_dbm),
        ("TX gain", tx_gain_dbi),
        ("RX gain", rx_gain_dbi),
        ("noise figure", noise_figure_db),
        ("required SNR", snr_req_db),
    ):
        finite(value, name)
    positive(distance_km, "distance (km)")
    positive(freq_ghz, "frequency (GHz)")
    positive(bw_mhz, "bandwidth (MHz)")
    fspl = 20 * math.log10(distance_km) + 20 * math.log10(freq_ghz) + 92.45
    received = tx_power_dbm + tx_gain_dbi - fspl + rx_gain_dbi
    noise = -174 + 10 * math.log10(bw_mhz * 1e6) + noise_figure_db
    snr = received - noise
    margin = snr - snr_req_db
    return {
        "fspl": fspl,
        "p_rx": received,
        "noise_power": noise,
        "snr": snr,
        "margin": margin,
        "status": "PASS" if margin > 0 else "FAIL",
    }
