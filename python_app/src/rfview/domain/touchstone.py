"""Strict Touchstone 1.x S-parameter parser for one- and two-port networks."""

import math
import re
from typing import Literal

from pydantic import BaseModel, ConfigDict

MAX_TOUCHSTONE_BYTES = 5 * 1024 * 1024
MAX_FREQUENCIES = 100_000


class TouchstonePoint(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    freq_ghz: float
    param: str
    real: float
    imag: float
    mag_linear: float
    mag_db: float
    phase_deg: float
    dataset_tag: str


class TouchstoneData(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    format: Literal["touchstone"] = "touchstone"
    filename: str
    nports: int
    freq_ghz: tuple[float, ...]
    freq_unit: str
    data_format: str
    param_type: Literal["s"] = "s"
    z0: float
    dataset_tag: str
    points: tuple[TouchstonePoint, ...]
    comments: tuple[str, ...]


def serialize_touchstone(network: TouchstoneData) -> str:
    """Export source S values as Touchstone 1.x GHz/RI; not the original text."""
    if network.nports not in (1, 2):
        raise ValueError("Touchstone export supports one or two ports only")
    parameters = ["S11"] if network.nports == 1 else ["S11", "S21", "S12", "S22"]
    width = len(parameters)
    if len(network.points) != len(network.freq_ghz) * width:
        raise ValueError("Export requires a complete record at every frequency")
    lines = [
        "! RFView source S-parameter export; original comments/formatting not retained",
        f"# GHz S RI R {network.z0:.17g}",
    ]
    for index, frequency in enumerate(network.freq_ghz):
        record = network.points[index * width : (index + 1) * width]
        if [point.param for point in record] != parameters or any(
            point.freq_ghz != frequency for point in record
        ):
            raise ValueError("Export requires Touchstone-ordered parameters at each frequency")
        tokens = [f"{frequency:.17g}"]
        for point in record:
            tokens.extend((f"{point.real:.17g}", f"{point.imag:.17g}"))
        lines.append(" ".join(tokens))
    text = "\n".join(lines) + "\n"
    # Apply the same size, finite-value and frequency rules as imported files.
    parse_touchstone(text, f"export.s{network.nports}p")
    return text


def parse_touchstone(text: str, filename: str, dataset_tag: str | None = None) -> TouchstoneData:
    if len(text.encode("utf-8")) > MAX_TOUCHSTONE_BYTES:
        raise ValueError("Touchstone exceeds the 5 MiB migration limit")
    name = re.split(r"[\\/]", filename)[-1]
    extension = re.search(r"\.s(\d+)p$", name, re.IGNORECASE)
    if extension is None or int(extension[1]) not in (1, 2):
        raise ValueError("This slice supports Touchstone 1.x .s1p/.s2p files only")
    nports = int(extension[1])
    unit, representation, z0 = "ghz", "ma", 50.0
    option_seen, data_seen = False, False
    comments: list[str] = []
    numbers: list[float] = []
    for line_number, original in enumerate(text.lstrip("\ufeff").splitlines(), 1):
        if original.lstrip().startswith("!"):
            comments.append(original)
        line = original.split("!", 1)[0].strip()
        if not line:
            continue
        if line.startswith("["):
            raise ValueError(f"Line {line_number}: Touchstone 2.x keywords are not supported")
        if line.startswith("#"):
            if option_seen or data_seen:
                raise ValueError(f"Line {line_number}: duplicate or late option line")
            option_seen = True
            tokens = line[1:].lower().split()
            if not tokens:
                continue
            if tokens[0] not in ("hz", "khz", "mhz", "ghz"):
                raise ValueError(f"Line {line_number}: unsupported frequency unit")
            unit = tokens[0]
            if len(tokens) >= 2 and tokens[1] != "s":
                raise ValueError(f"Line {line_number}: only S-parameters are supported")
            if len(tokens) >= 3:
                if tokens[2] not in ("ri", "ma", "db"):
                    raise ValueError(f"Line {line_number}: unsupported data representation")
                representation = tokens[2]
            if len(tokens) > 3:
                if len(tokens) != 5 or tokens[3] != "r":
                    raise ValueError(f"Line {line_number}: expected R followed by impedance")
                try:
                    z0 = float(tokens[4])
                except ValueError as exc:
                    raise ValueError(f"Line {line_number}: invalid reference impedance") from exc
                if not math.isfinite(z0) or z0 <= 0:
                    raise ValueError(f"Line {line_number}: impedance must be finite and positive")
            continue
        data_seen = True
        for token in line.split():
            try:
                value = float(token.replace("D", "E").replace("d", "e"))
            except ValueError as exc:
                raise ValueError(f"Line {line_number}: invalid numeric token {token!r}") from exc
            if not math.isfinite(value):
                raise ValueError(f"Line {line_number}: nonfinite numeric value")
            numbers.append(value)
    width = 1 + 2 * nports**2
    if not numbers or len(numbers) % width:
        raise ValueError(f"Incomplete Touchstone records: expected multiples of {width} values")
    if len(numbers) // width > MAX_FREQUENCIES:
        raise ValueError(f"Touchstone exceeds {MAX_FREQUENCIES} frequency records")
    tag = dataset_tag if dataset_tag is not None else name.rsplit(".", 1)[0]
    if not tag.strip():
        raise ValueError("Dataset tag must not be empty")
    scale = {"hz": 1e-9, "khz": 1e-6, "mhz": 1e-3, "ghz": 1}[unit]
    frequencies: list[float] = []
    points: list[TouchstonePoint] = []
    for offset in range(0, len(numbers), width):
        freq = numbers[offset] * scale
        if freq < 0 or (frequencies and freq <= frequencies[-1]):
            raise ValueError("Frequencies must be nonnegative and strictly increasing")
        frequencies.append(freq)
        for index in range(nports**2):
            a, b = numbers[offset + 1 + 2 * index : offset + 3 + 2 * index]
            if representation == "ri":
                real, imag = a, b
            else:
                if representation == "ma" and a < 0:
                    raise ValueError("Magnitude-angle values require nonnegative magnitudes")
                try:
                    magnitude = 10 ** (a / 20) if representation == "db" else a
                except OverflowError as exc:
                    raise ValueError("Touchstone magnitude exceeds numeric range") from exc
                phase = math.radians(b)
                real, imag = magnitude * math.cos(phase), magnitude * math.sin(phase)
            magnitude = math.hypot(real, imag)
            points.append(
                TouchstonePoint(
                    freq_ghz=freq,
                    param=f"S{index % nports + 1}{index // nports + 1}",
                    real=real,
                    imag=imag,
                    mag_linear=magnitude,
                    mag_db=20 * math.log10(max(magnitude, 1e-15)),
                    phase_deg=math.degrees(math.atan2(imag, real)),
                    dataset_tag=tag,
                )
            )
    return TouchstoneData(
        filename=name,
        nports=nports,
        freq_ghz=tuple(frequencies),
        freq_unit=unit,
        data_format=representation,
        z0=z0,
        dataset_tag=tag,
        points=tuple(points),
        comments=tuple(comments),
    )
