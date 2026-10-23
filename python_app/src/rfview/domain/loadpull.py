"""Bounded load-pull ASCII adapters with explicit units and no measurement repair."""

import csv
import math
import re
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

LoadPullFormat = Literal[
    "spl", "focus", "lpcwave", "mdf", "amcad", "anteverta", "mdif", "cst", "alps_mdf", "spl_plan"
]
MAX_LOADPULL_BYTES = 5 * 1024 * 1024
MAX_LOADPULL_POINTS = 100_000


class LoadPullPoint(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    gl_r: float
    gl_i: float
    gs_r: float | None = None
    gs_i: float | None = None
    pout_dbm: float | None = None
    pin_dbm: float | None = None
    pout_w: float | None = None
    pin_w: float | None = None
    gain_db: float | None = None
    pae_pct: float | None = None
    de_pct: float | None = None
    idc_a: float | None = None
    vdc_v: float | None = None
    pdc_w: float | None = None
    freq_ghz: float | None = None
    extra: dict[str, float | None] = Field(default_factory=dict)
    source_strings: dict[str, str] = Field(default_factory=dict)


class LoadPullData(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    model_version: Literal["rfview-loadpull-v1"] = "rfview-loadpull-v1"
    filename: str
    format: LoadPullFormat
    points: tuple[LoadPullPoint, ...]
    metadata: dict[str, str]
    warnings: tuple[str, ...]


_GROUPS = {
    "gl_r": (
        "GL_R GL_REAL GAMMA_L_R GAMMAL_R GAMMAL_REAL GL_RE LOAD_R "
        "GAMMA_LD1_RE GAMMA_LD1_RE_VAL GLRE"
    ),
    "gl_i": (
        "GL_I GL_IMAG GAMMA_L_I GAMMAL_I GAMMAL_IMAG GL_IM LOAD_I "
        "GAMMA_LD1_IM GAMMA_LD1_IM_VAL GLIM"
    ),
    "gl_mag": "GAMMA_L_MAG GL_MAG GAMMAL_MAG",
    "gl_ang": "GAMMA_L_ANG GL_ANG GAMMAL_ANG GAMMA_L_PHASE GL_PHASE",
    "gs_r": "GS_R GS_REAL GAMMA_S_R GAMMAS_R GAMMA_SRC1_RE GAMMA_SRC1_RE_VAL GSRE",
    "gs_i": "GS_I GS_IMAG GAMMA_S_I GAMMAS_I GAMMA_SRC1_IM GAMMA_SRC1_IM_VAL GSIM",
    "gs_mag": "GAMMA_S_MAG GS_MAG",
    "gs_ang": "GAMMA_S_ANG GS_ANG GAMMA_S_PHASE",
    "pout_dbm": "POUT POUT(DBM) POUT_DBM OUTPUTPOWER POUTWAVES POUT_DBM_COMPRCON",
    "pin_dbm": "PIN PIN(DBM) PIN_DBM PAV PAVS AVAIL_POWER BO PIN_AVAIL_DBM PINWAVES",
    "gain_db": "GAIN GAIN(DB) GAIN_DB GT TRANSDUCER_GAIN GT_DB GAINWAVESTRD GT_DB_COMPRCON",
    "pae_pct": "PAE PAE(%) PAE_PCT PAE(PERCENT) PAE_COMPRCON",
    "de_pct": "DE DE(%) DE_PCT EFF DRAIN_EFF EFF_% EFF_COL EFF_ DE_VNA_PA_SCOPEEQN",
    "idc_a": "IDC IDC(A) IDC_A IDS IDRAIN",
    "idc_ma": "IDC(MA) IQ_OUT_MA IOUT_MA I2",
    "vdc_v": "VDC VDC(V) VDC_V VDS VDRAIN VQ_IN_V V2",
    "pdc_w": "PDC PDC(W) PDC_W PDIS",
    "pout_w": "POUT_W POUTW POUTW_COMPRCON",
    "pin_w": "PIN_W",
    "freq_ghz": "FREQ FREQ(GHZ) FREQUENCY FRQ FREQ_GHZ",
}
_ALIASES = {alias: canonical for canonical, aliases in _GROUPS.items() for alias in aliases.split()}
_NUMBER = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eEdD][+-]?\d+)?"


def _number(token: str, context: str) -> float | None:
    if token.upper() in ("N/A", "NA", ""):
        return None
    try:
        value = float(token.replace("D", "E").replace("d", "e"))
    except ValueError as exc:
        raise ValueError(f"{context}: invalid numeric token {token!r}") from exc
    if not math.isfinite(value):
        raise ValueError(f"{context}: nonfinite measurement")
    return value


def _csv_fields(line: str, line_number: int) -> list[str]:
    try:
        return next(csv.reader([line], skipinitialspace=True, strict=True))
    except csv.Error as exc:
        raise ValueError(f"Line {line_number}: invalid CSV: {exc}") from exc


def _frequency(text: str) -> float:
    match = re.fullmatch(rf"\s*({_NUMBER})\s*(GHz|MHz|kHz|Hz)?\s*", text, re.I)
    if match is None:
        raise ValueError(f"Invalid frequency metadata: {text!r}")
    value = _number(match[1], "frequency")
    assert value is not None
    value *= {"ghz": 1, "mhz": 1e-3, "khz": 1e-6, "hz": 1e-9}[(match[2] or "GHz").lower()]
    if not math.isfinite(value) or value < 0:
        raise ValueError("Frequency must be finite and nonnegative")
    return value


def _header(text: str, *, expand_gamma: bool = False) -> list[str]:
    columns = text.upper().split()
    result: list[str] = []
    for column in columns:
        if (
            expand_gamma
            and column.startswith("GAMMA_")
            and not column.endswith(
                ("_RE", "_IM", "_REAL", "_IMAG", "_R", "_I", "_MAG", "_ANG", "_PHASE")
            )
        ):
            result.extend((column + "_RE", column + "_IM"))
        else:
            result.append(column)
    if len(result) < 2 or len(set(result)) != len(result):
        raise ValueError("Load-pull columns must be distinct and contain at least two fields")
    return result


def _row(columns: list[str], tokens: list[str], line: int) -> dict[str, float | None]:
    if len(tokens) != len(columns):
        raise ValueError(f"Line {line}: expected {len(columns)} fields, received {len(tokens)}")
    return {
        column: _number(value, f"Line {line}, {column}")
        for column, value in zip(columns, tokens, strict=True)
    }


def _polar(magnitude: float, angle: float) -> tuple[float, float]:
    if magnitude < 0:
        raise ValueError("Reflection-coefficient magnitude must not be negative")
    radians = math.radians(angle)
    return magnitude * math.cos(radians), magnitude * math.sin(radians)


def normalise_loadpull_row(
    raw: dict[str, float | None],
    frequency: float | None,
    efficiency_unit: str,
    warnings: dict[str, None],
    row_index: int,
) -> LoadPullPoint:
    values: dict[str, float | None] = {}
    for key, value in raw.items():
        canonical = _ALIASES.get(key, key.lower())
        if canonical in values:
            raise ValueError(f"Row {row_index}: ambiguous aliases for {canonical}")
        values[canonical] = value
    for prefix in ("gl", "gs"):
        real, imag, mag, ang = (
            values.get(prefix + suffix) for suffix in ("_r", "_i", "_mag", "_ang")
        )
        if real is None and imag is None and mag is not None and ang is not None:
            values[prefix + "_r"], values[prefix + "_i"] = _polar(mag, ang)
        elif (real is None) != (imag is None):
            raise ValueError(f"Row {row_index}: incomplete {prefix} Cartesian pair")
    load_real, load_imag = values.get("gl_r"), values.get("gl_i")
    if load_real is None or load_imag is None:
        raise ValueError(f"Row {row_index}: load reflection coefficient is required")
    milliamps = values.get("idc_ma")
    if values.get("idc_a") is None and milliamps is not None:
        values["idc_a"] = milliamps / 1000
    if values.get("pdc_w") is None:
        voltage, current = values.get("vdc_v"), values.get("idc_a")
        if voltage is not None and current is not None:
            values["pdc_w"] = voltage * current
    for name in ("pout", "pin"):
        dbm, watts = values.get(name + "_dbm"), values.get(name + "_w")
        if watts is None and dbm is not None:
            values[name + "_w"] = 10 ** ((dbm - 30) / 10)
        elif dbm is None and watts is not None and watts > 0:
            values[name + "_dbm"] = 10 * math.log10(watts) + 30
    for key in ("pae_pct", "de_pct"):
        value = values.get(key)
        if value is not None and efficiency_unit == "fraction":
            values[key] = value * 100
    pout, pin, pdc = values.get("pout_w"), values.get("pin_w"), values.get("pdc_w")
    if pdc is not None and pdc > 0 and pout is not None:
        if values.get("de_pct") is None:
            values["de_pct"] = pout / pdc * 100
        if values.get("pae_pct") is None and pin is not None:
            values["pae_pct"] = (pout - pin) / pdc * 100
    elif pdc is not None and pdc <= 0:
        warnings[f"Row {row_index}: nonpositive DC power; derived efficiencies are undefined."] = (
            None
        )
    if values.get("freq_ghz") is None:
        values["freq_ghz"] = frequency
    freq = values["freq_ghz"]
    if freq is not None and freq < 0:
        raise ValueError(f"Row {row_index}: frequency must not be negative")
    for key in ("pae_pct", "de_pct"):
        value = values.get(key)
        if value is not None and not 0 <= value <= 100:
            warnings[
                f"Row {row_index}: {key} outside 0-100 %; measurement retained, not repaired."
            ] = None
    pae, de = values.get("pae_pct"), values.get("de_pct")
    if pae is not None and de is not None and pae > de:
        warnings[f"Row {row_index}: PAE exceeds DE; measurement retained, not capped."] = None
    if math.hypot(load_real, load_imag) > 1 + 1e-12:
        warnings[
            f"Row {row_index}: |Gamma_load| > 1; active/out-of-calibration value retained."
        ] = None
    known = {
        key: value
        for key, value in values.items()
        if key in LoadPullPoint.model_fields and key != "extra"
    }
    extra = {key: value for key, value in values.items() if key not in known}
    return LoadPullPoint.model_validate({**known, "extra": extra})


def parse_loadpull(
    text: str,
    filename: str,
    format: LoadPullFormat,
    *,
    efficiency_unit: Literal["percent", "fraction"] = "percent",
) -> LoadPullData:
    """Parse an explicitly selected vendor adapter; never guess efficiency units."""
    if len(text.encode("utf-8")) > MAX_LOADPULL_BYTES:
        raise ValueError("Load-pull exceeds the 5 MiB limit")
    if format not in ("spl", "focus", "lpcwave", "mdf", "amcad", "anteverta", "mdif", "cst"):
        raise ValueError("Unsupported load-pull adapter")
    if efficiency_unit not in ("percent", "fraction"):
        raise ValueError("Efficiency unit must be percent or fraction")
    if format == "cst":
        return _parse_cst(text, filename)
    metadata: dict[str, str] = {}
    warnings: dict[str, None] = {
        "Explicit efficiency units replace the legacy <=1.01 guessing heuristic; "
        "no efficiency clipping/repair is performed.": None
    }
    columns: list[str] | None = None
    rows: list[dict[str, float | None]] = []
    frequency: float | None = None
    in_block = False
    in_mdif = False
    variables: dict[str, float | None] = {}
    gamma: tuple[float, float] | None = None
    skipped = 0
    for line_number, original in enumerate(text.lstrip("\ufeff").splitlines(), 1):
        line = original.strip()
        if not line:
            continue
        upper = line.upper()
        meta = re.match(r"^[!#%]\s*(FREQ(?:UENCY)?(?:_GHZ)?)(?:\s*[:=]\s*|\s+)(.+)$", line, re.I)
        section = re.match(r"^FREQ\s*=\s*(.+)$", line, re.I)
        if meta is not None or section is not None:
            frequency_text = (
                meta[2] if meta is not None else section[1] if section is not None else ""
            )
            frequency = _frequency(frequency_text)
            metadata["frequency"] = f"{frequency:.17g} GHz"
            continue
        if format == "lpcwave":
            header = re.sub(r"^!+\s*", "", line)
            if re.match(r"POINT\s+GAMMA\s+", header, re.I):
                clean = re.sub(r"\[[^]]*\]", "", header)
                columns = ["GL_R", "GL_I", *_header(clean)[3:]]
                continue
            if line.startswith("#"):
                tokens = line[1:].split()
                if len(tokens) not in (2, 3):
                    raise ValueError(f"Line {line_number}: invalid load-point descriptor")
                magnitude, angle = (_number(token, f"Line {line_number}") for token in tokens[-2:])
                if magnitude is None or angle is None:
                    raise ValueError(f"Line {line_number}: missing load-point Gamma")
                gamma = _polar(magnitude, angle)
                continue
        if line.startswith(("!", "#")):
            metadata[f"line_{line_number}"] = line
            continue
        if format in ("mdf", "mdif"):
            if re.match(r"BEGIN\s+MDIF\b", upper):
                if in_mdif:
                    raise ValueError(f"Line {line_number}: nested MDIF")
                in_mdif, variables, frequency = True, {}, None
                continue
            if re.match(r"END\s+MDIF\b", upper):
                if not in_mdif or in_block:
                    raise ValueError(f"Line {line_number}: malformed MDIF block")
                in_mdif = False
                continue
            if re.match(r"BEGIN\s+(SWEEP|DATA|ACDATA)\b", upper):
                if in_block or (format == "mdif" and not in_mdif):
                    raise ValueError(f"Line {line_number}: invalid data block")
                in_block, columns = True, None
                continue
            if re.match(r"END\s+(SWEEP|DATA|ACDATA)\b", upper):
                if not in_block:
                    raise ValueError(f"Line {line_number}: unexpected END")
                in_block = False
                continue
            if upper.startswith("VAR "):
                match = re.match(r"VAR\s+(\w+)(?:\(\w+\))?\s*(?:=\s*|\w+\s+)(.+)$", line, re.I)
                if match is None:
                    raise ValueError(f"Line {line_number}: unsupported VAR declaration")
                key, raw_value = match[1].upper(), match[2].strip()
                metadata[key] = raw_value
                if key in ("FREQ", "FREQUENCY", "FREQ_GHZ"):
                    frequency = _frequency(raw_value)
                elif format == "mdif":
                    variables[key] = _number(raw_value, f"Line {line_number}")
                continue
            if not in_block:
                metadata[f"line_{line_number}"] = line
                continue
        if columns is None:
            if format in ("amcad", "anteverta"):
                if line.startswith(("%", "AMCAD", "ANTEVERTA")) or "," not in line:
                    metadata[f"line_{line_number}"] = line
                    continue
                columns = _csv_fields(line, line_number)
                columns = _header(" ".join(token.strip() for token in columns))
            else:
                clean = line.lstrip("%").strip()
                if format == "mdf":
                    if "(string)" in clean.lower():
                        raise ValueError(
                            "MDF string columns require a separately qualified adapter"
                        )
                    clean = re.sub(r"\(real\)|\(integer\)", "", clean, flags=re.I)
                if not all(
                    re.fullmatch(r"[A-Za-z_][A-Za-z0-9_%()]*", token) for token in clean.split()
                ):
                    if format == "spl":
                        metadata[f"line_{line_number}"] = line
                        continue
                    raise ValueError(f"Line {line_number}: expected a column header")
                columns = _header(clean, expand_gamma=format == "spl")
            continue
        if upper == " ".join(columns):
            continue
        if (
            format == "spl"
            and all(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_%()]*", token) for token in line.split())
            and _header(line, expand_gamma=True) == columns
        ):
            continue
        tokens = (
            _csv_fields(line, line_number) if format in ("amcad", "anteverta") else line.split()
        )
        if format == "lpcwave":
            if gamma is None:
                raise ValueError(f"Line {line_number}: data precedes a load-point descriptor")
            tokens = [repr(gamma[0]), repr(gamma[1]), *tokens]
        raw = _row(columns, tokens, line_number)
        if raw.get("VALID") == 0:
            skipped += 1
            continue
        raw.update(variables)
        if "FREQ_GHZ" not in raw and not any(_ALIASES.get(k) == "freq_ghz" for k in raw):
            raw["FREQ_GHZ"] = frequency
        rows.append(raw)
        if len(rows) > MAX_LOADPULL_POINTS:
            raise ValueError(f"Load-pull exceeds {MAX_LOADPULL_POINTS} points")
    if in_block or in_mdif:
        raise ValueError("Unclosed load-pull data block")
    if not rows:
        raise ValueError("No load-pull measurement rows found")
    if skipped:
        warnings[f"Skipped {skipped} rows explicitly marked VALID=0."] = None
    try:
        points = tuple(
            normalise_loadpull_row(row, None, efficiency_unit, warnings, i + 1)
            for i, row in enumerate(rows)
        )
    except OverflowError as exc:
        raise ValueError("Load-pull calculation exceeds numeric range") from exc
    return LoadPullData(
        filename=re.split(r"[\\/]", filename)[-1],
        format=format,
        points=points,
        metadata=metadata,
        warnings=tuple(warnings),
    )


def _parse_cst(text: str, filename: str) -> LoadPullData:
    points: list[LoadPullPoint] = []
    metadata: dict[str, str] = {}
    warnings: dict[str, None] = {
        "CST assumes peak voltage waves: power=(|a|^2-|b|^2)/(2*Z0). "
        "Confirm wave normalization/calibration before engineering use.": None,
        "CST uses each port's reference impedance; unlike R it does not reuse "
        "source Z0 for output power, clamp negative power, or call the broken "
        "three-argument normalizer.": None,
    }
    active = False
    state: dict[str, float] = {}
    header_seen = False
    for line_number, original in enumerate(text.lstrip("\ufeff").splitlines(), 1):
        line = original.strip()
        if not line or line.startswith("!"):
            continue
        upper = line.upper()
        if upper == "#BEGIN":
            if active:
                raise ValueError(f"Line {line_number}: nested CST block")
            active, header_seen = True, False
            state = {"z0source": 50, "z0load": 50}
            continue
        if upper == "#END":
            if not active:
                raise ValueError(f"Line {line_number}: unexpected CST END")
            active = False
            continue
        if line.startswith("#"):
            match = re.match(
                r"^#(Z0SOURCE|Z0LOAD|GAMMALOAD|GAMMASOURCE|FUNDAMENTAL FREQUENCY)\s*:?\s+(.+)$",
                line,
                re.I,
            )
            if match is not None:
                if not active:
                    raise ValueError(f"Line {line_number}: CST block metadata must follow #BEGIN")
                key, raw = match[1].lower(), match[2]
                if key == "fundamental frequency":
                    # Unitless legacy CST metadata is Hz when >1e6, GHz otherwise.
                    value = _frequency(raw)
                    if not re.search(r"(?:ghz|mhz|khz|hz)\s*$", raw, re.I) and value > 1e6:
                        value /= 1e9
                    state["freq_ghz"] = value
                elif key.startswith("z0"):
                    impedance = _number(raw, f"Line {line_number}")
                    if impedance is None or impedance <= 0:
                        raise ValueError("CST reference impedance must be positive")
                    state[key] = impedance
                else:
                    tokens = raw.split()
                    if len(tokens) != 2:
                        raise ValueError("CST Gamma requires magnitude and angle in degrees")
                    mag, angle = (_number(v, f"Line {line_number}") for v in tokens)
                    if mag is None or angle is None:
                        raise ValueError("Missing CST Gamma descriptor")
                    real, imag = _polar(mag, angle)
                    prefix = "GL" if key == "gammaload" else "GS"
                    state[prefix + "_R"], state[prefix + "_I"] = real, imag
            metadata[f"line_{line_number}"] = line
            continue
        if not active:
            raise ValueError(f"Line {line_number}: CST data outside a block")
        if not header_seen and not re.match(r"^[+-]?(?:\d|\.)", line):
            header_seen = True
            continue
        tokens = line.split()
        if len(tokens) != 13:
            raise ValueError(f"Line {line_number}: CST requires 13 numeric fields")
        numeric = [_number(token, f"Line {line_number}") for token in tokens]
        if any(v is None for v in numeric):
            raise ValueError(f"Line {line_number}: missing CST wave quantity")
        nums = [v for v in numeric if v is not None]
        try:
            frequency = nums[0] / 1e9
            if "freq_ghz" in state and not math.isclose(
                state["freq_ghz"], frequency, rel_tol=1e-9, abs_tol=1e-12
            ):
                raise ValueError("CST harmonic/mismatched frequencies require separate selection")
            pin = ((nums[5] ** 2 + nums[6] ** 2) - (nums[7] ** 2 + nums[8] ** 2)) / (
                2 * state["z0source"]
            )
            pout = ((nums[11] ** 2 + nums[12] ** 2) - (nums[9] ** 2 + nums[10] ** 2)) / (
                2 * state["z0load"]
            )
            raw_values: dict[str, float | None] = {
                "GL_R": state.get("GL_R"),
                "GL_I": state.get("GL_I"),
                "GS_R": state.get("GS_R"),
                "GS_I": state.get("GS_I"),
                "PIN_W": pin,
                "POUT_W": pout,
                "VDC_V": nums[3],
                "IDC_A": nums[4],
                "FREQ_GHZ": frequency,
            }
            if pin <= 0 or pout <= 0:
                warnings[
                    f"Row {len(points) + 1}: nonpositive net wave power; dBm/gain undefined."
                ] = None
            if pin > 0 and pout > 0:
                raw_values["GAIN_DB"] = 10 * (math.log10(pout) - math.log10(pin))
            points.append(
                normalise_loadpull_row(raw_values, frequency, "percent", warnings, len(points) + 1)
            )
        except OverflowError as exc:
            raise ValueError("CST calculation exceeds numeric range") from exc
        if len(points) > MAX_LOADPULL_POINTS:
            raise ValueError(f"Load-pull exceeds {MAX_LOADPULL_POINTS} points")
    if active:
        raise ValueError("Unclosed CST block")
    if not points:
        raise ValueError("No CST measurement rows found")
    return LoadPullData(
        filename=re.split(r"[\\/]", filename)[-1],
        format="cst",
        points=tuple(points),
        metadata=metadata,
        warnings=tuple(warnings),
    )
