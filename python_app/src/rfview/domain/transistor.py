import math

from rfview.domain.models import finite, nonnegative, positive

ScalarResult = dict[str, float | str | None]

VKNEE = {
    "gan_sic": 2.0,
    "gan": 2.0,
    "gan hemt": 2.0,
    "gan_si": 1.5,
    "ldmos": 3.0,
    "si ldmos": 3.0,
    "gaas": 0.3,
    "gaas phemt": 0.3,
    "sige": 0.4,
    "sige hbt": 0.4,
    "inp": 0.2,
    "inp hemt": 0.2,
}


def default_vknee(technology: str = "GaN_SiC") -> float:
    key = technology.strip().lower()
    if key not in VKNEE:
        raise ValueError(f"Unknown technology: {technology}")
    return VKNEE[key]


def ropt(
    vdd_v: float, pout_w: float, vknee_v: float | None = None, technology: str = "GaN_SiC"
) -> float:
    positive(vdd_v, "Vdd (V)")
    positive(pout_w, "Pout (W)")
    knee = default_vknee(technology) if vknee_v is None else nonnegative(vknee_v, "Vknee (V)")
    if vdd_v <= knee:
        raise ValueError("Vdd must exceed Vknee")
    return (vdd_v - knee) ** 2 / (2 * pout_w)


def gate_width(pout_w: float, power_density_w_per_mm: float, pae_frac: float) -> float:
    positive(pout_w, "Pout (W)")
    positive(power_density_w_per_mm, "power density (W/mm)")
    finite(pae_frac, "PAE fraction")
    if not 0 < pae_frac <= 1:
        raise ValueError("PAE fraction must be in (0, 1]")
    return pout_w / power_density_w_per_mm


def idq(ids_max_ma: float, conduction_angle_deg: float = 240) -> ScalarResult:
    nonnegative(ids_max_ma, "maximum current (mA)")
    finite(conduction_angle_deg, "conduction angle (deg)")
    if not 180 <= conduction_angle_deg <= 360:
        raise ValueError("Conduction angle must be in [180, 360] deg")
    label = (
        "Class B"
        if conduction_angle_deg == 180
        else "Class A"
        if conduction_angle_deg == 360
        else "Class AB"
    )
    return {
        "Idq_mA": ids_max_ma * (conduction_angle_deg - 180) / 360,
        "class_label": label,
        "conduction_angle_deg": conduction_angle_deg,
        "Ids_max_mA": ids_max_ma,
    }


def doherty_sizing(ropt_main_ohm: float, topology: str = "symmetric") -> ScalarResult:
    positive(ropt_main_ohm, "Ropt (ohm)")
    factors = {"symmetric": 2, "asymmetric_6dB": 2, "asymmetric_9dB": 3}
    if topology not in factors:
        raise ValueError(f"Unsupported Doherty topology: {topology}")
    factor = factors[topology]
    return {
        "Ropt_main_ohm": ropt_main_ohm,
        "Ropt_peak_ohm": factor * ropt_main_ohm,
        "Zt_ohm": math.sqrt(ropt_main_ohm * 50),
        "n_factor": factor,
        "gate_ratio": 1.0 if topology == "symmetric" else factor,
        "topology": topology,
    }


def matching_lmatch(zs_ohm: float, zl_ohm: float, freq_ghz: float) -> ScalarResult:
    positive(zs_ohm, "source impedance (ohm)")
    positive(zl_ohm, "load impedance (ohm)")
    positive(freq_ghz, "frequency (GHz)")
    base: ScalarResult = {"Zs_ohm": zs_ohm, "Zl_ohm": zl_ohm, "freq_ghz": freq_ghz}
    if math.isclose(zs_ohm, zl_ohm, rel_tol=1.49e-8):
        return base | {"Q": 0, "L_nH": None, "C_pF": None, "bw_pct": None, "topology": "none"}
    high, low = max(zs_ohm, zl_ohm), min(zs_ohm, zl_ohm)
    q = math.sqrt(high / low - 1)
    omega = 2 * math.pi * freq_ghz * 1e9
    if zs_ohm > zl_ohm:
        inductance, capacitance = q * low / omega * 1e9, q / (omega * high) * 1e12
        topology = "step_down_L"
    else:
        inductance = high / (q * omega) * 1e9
        capacitance = 1 / (q * omega * low) * 1e12
        topology = "step_up_C"
    return base | {
        "Q": q,
        "L_nH": inductance,
        "C_pF": capacitance,
        "bw_pct": 100 / q,
        "topology": topology,
    }


def doherty_combiner(
    ropt_main_ohm: float, freq_ghz: float, er: float = 3.55, h_mm: float = 0.508
) -> ScalarResult:
    positive(ropt_main_ohm, "Ropt (ohm)")
    positive(freq_ghz, "frequency (GHz)")
    positive(h_mm, "substrate thickness (mm)")
    finite(er, "relative permittivity")
    if er < 1:
        raise ValueError("Relative permittivity must be at least 1")
    zt = math.sqrt(ropt_main_ohm * 50)
    wavelength = 299792.458 / (freq_ghz * 1000 * math.sqrt(er))
    a = (zt / 60) * math.sqrt((er + 1) / 2) + (er - 1) / (er + 1) * (0.23 + 0.11 / er)
    exp_negative_a = math.exp(-a)
    narrow = 8 * exp_negative_a / (1 - 2 * exp_negative_a**2)
    if 0 < narrow < 2:
        width_ratio = narrow
    else:
        b = 377 * math.pi / (2 * zt * math.sqrt(er))
        if b <= 1:
            raise ValueError("Impedance outside the supported microstrip approximation")
        width_ratio = (2 / math.pi) * (
            b - 1 - math.log(2 * b - 1) + (er - 1) / (2 * er) * (math.log(b - 1) + 0.39 - 0.61 / er)
        )
    positive(width_ratio, "microstrip width ratio")
    return {
        "Zt_ohm": zt,
        "len_mm": wavelength / 4,
        "width_mm": width_ratio * h_mm,
        "lambda_g_mm": wavelength,
        "er": er,
        "h_mm": h_mm,
        "freq_ghz": freq_ghz,
    }
