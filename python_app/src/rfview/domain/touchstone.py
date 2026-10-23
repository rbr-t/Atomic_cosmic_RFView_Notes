"""Bounded Touchstone 1.x/2.0 full-matrix S-parameters for one to nine ports."""

import math
import re
from typing import Literal, NamedTuple

from pydantic import BaseModel, ConfigDict

from rfview.domain.network_parameters import s_to_abcd, s_to_h, s_to_t, s_to_y, s_to_z

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
    version: Literal["1.0", "2.0"] = "1.0"
    reference_ohms: tuple[float, ...] = ()


class ConvertedParameter(NamedTuple):
    freq_ghz: float
    parameter: str
    unit: str
    value: complex


def converted_parameters(
    network: TouchstoneData, representation: str
) -> tuple[ConvertedParameter, ...]:
    if representation not in ("Z", "Y", "h", "ABCD", "T"):
        raise ValueError("Converted export/view requires Z, Y, h, ABCD or T")
    if network.nports != 2:
        raise ValueError("Parameter conversion requires a two-port dataset")
    references = network.reference_ohms or (network.z0,) * 2
    if representation != "T" and len(set(references)) != 1:
        raise ValueError(
            "Converted Z/Y/h/ABCD views require a common real reference impedance; "
            "unequal per-port references are preserved in source S, not silently renormalized"
        )
    result: list[ConvertedParameter] = []
    for offset, frequency in enumerate(network.freq_ghz):
        values = {
            point.param: complex(point.real, point.imag)
            for point in network.points[offset * 4 : offset * 4 + 4]
        }
        if set(values) != {"S11", "S12", "S21", "S22"}:
            raise ValueError("Conversion requires complete two-port records at every frequency")
        matrix = ((values["S11"], values["S12"]), (values["S21"], values["S22"]))
        try:
            converted = (
                s_to_t(matrix)
                if representation == "T"
                else {
                    "Z": s_to_z,
                    "Y": s_to_y,
                    "h": s_to_h,
                    "ABCD": s_to_abcd,
                }[representation](matrix, references[0])
            )
        except ValueError as exc:
            raise ValueError(
                f"{representation} conversion failed at {frequency:g} GHz: {exc}. "
                "No partial curve/export is produced; select S to view source data."
            ) from exc
        for row in range(2):
            for col in range(2):
                label = (
                    "ABCD"[row * 2 + col]
                    if representation == "ABCD"
                    else f"{representation}{row + 1}{col + 1}"
                )
                unit = {"Z": "ohm", "Y": "S", "T": "dimensionless"}.get(
                    representation, "dimensionless"
                )
                if representation == "h":
                    unit = "ohm" if (row, col) == (0, 0) else "S" if (row, col) == (1, 1) else unit
                elif representation == "ABCD":
                    unit = "ohm" if (row, col) == (0, 1) else "S" if (row, col) == (1, 0) else unit
                result.append(ConvertedParameter(frequency, label, unit, converted[row][col]))
    return tuple(result)


def serialize_converted_parameters(network: TouchstoneData, representation: str) -> str:
    """All four converted parameters, not just the selected trace, with units and references."""
    rows = converted_parameters(network, representation)
    references = network.reference_ohms or (network.z0,) * 2
    lines = [
        "frequency_ghz,representation,parameter,unit,real,imag,"
        "source_z0_port1_ohm,source_z0_port2_ohm"
    ]
    for row in rows:
        lines.append(
            f"{row.freq_ghz:.17g},{representation},{row.parameter},{row.unit},"
            f"{row.value.real:.17g},{row.value.imag:.17g},"
            f"{references[0]:.17g},{references[1]:.17g}"
        )
    text = "\n".join(lines) + "\n"
    if len(text.encode("utf-8")) > MAX_TOUCHSTONE_BYTES:
        raise ValueError("Converted CSV export exceeds the 5 MiB limit")
    return text


def serialize_touchstone(network: TouchstoneData) -> str:
    """Export source S in GHz/RI, retaining v2/per-port references, not original text."""
    if not 1 <= network.nports <= 9:
        raise ValueError("Touchstone export supports one to nine ports only")
    parameters = (
        ["S11", "S21", "S12", "S22"]
        if network.nports == 2
        else [
            f"S{r}{c}" for r in range(1, network.nports + 1) for c in range(1, network.nports + 1)
        ]
    )
    width = len(parameters)
    if len(network.points) != len(network.freq_ghz) * width:
        raise ValueError("Export requires a complete record at every frequency")
    references = network.reference_ohms or (network.z0,) * network.nports
    if len(references) != network.nports or any(not math.isfinite(v) or v <= 0 for v in references):
        raise ValueError("Export requires one positive finite reference impedance per port")
    lines = ["! RFView source S-parameter export; original comments/formatting not retained"]
    export_v2 = network.version == "2.0" or len(set(references)) != 1
    if export_v2:
        lines.extend(
            (
                "[Version] 2.0",
                f"# GHz S RI R {references[0]:.17g}",
                f"[Number of Ports] {network.nports}",
                f"[Number of Frequencies] {len(network.freq_ghz)}",
                "[Reference] " + " ".join(f"{value:.17g}" for value in references),
                "[Matrix Format] Full",
            )
        )
        if network.nports == 2:
            lines.append("[Two-Port Data Order] 21_12")
        lines.append("[Network Data]")
    else:
        lines.append(f"# GHz S RI R {network.z0:.17g}")
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
    if export_v2:
        text += "[End]\n"
    # Apply the same size, finite-value and frequency rules as imported files.
    parse_touchstone(text, f"export.s{network.nports}p")
    return text


def parse_touchstone(text: str, filename: str, dataset_tag: str | None = None) -> TouchstoneData:
    if len(text.encode("utf-8")) > MAX_TOUCHSTONE_BYTES:
        raise ValueError("Touchstone exceeds the 5 MiB migration limit")
    name = re.split(r"[\\/]", filename)[-1]
    if re.search(r"^\s*\[Version\]", text.lstrip("\ufeff"), re.I | re.M):
        return _parse_touchstone_v2(text, name, dataset_tag)
    extension = re.search(r"\.s(\d+)p$", name, re.IGNORECASE)
    if extension is None or not 1 <= int(extension[1]) <= 9:
        raise ValueError("Touchstone 1.x supports .s1p through .s9p; .ts requires Version 2.0")
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
                    param=(
                        f"S{index % nports + 1}{index // nports + 1}"
                        if nports == 2
                        else f"S{index // nports + 1}{index % nports + 1}"
                    ),
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


def _parse_touchstone_v2(text: str, filename: str, dataset_tag: str | None) -> TouchstoneData:
    declarations: dict[str, str] = {}
    options: list[str] = []
    network_lines: list[str] = []
    comments: list[str] = []
    in_network = ended = False
    reference_continuation = False
    for line_number, original in enumerate(text.lstrip("\ufeff").splitlines(), 1):
        if original.lstrip().startswith("!"):
            comments.append(original)
        line = original.split("!", 1)[0].strip()
        if not line:
            continue
        if ended:
            raise ValueError(f"Line {line_number}: content follows Touchstone [End]")
        if not declarations and not re.fullmatch(r"\[Version\]\s+2\.0", line, re.I):
            raise ValueError("Touchstone 2.0 must start with [Version] 2.0")
        keyword = re.fullmatch(r"\[([^]]+)\]\s*(.*)", line)
        if keyword is not None:
            reference_continuation = False
            key, value = keyword[1].lower(), keyword[2].strip()
            if key == "end":
                if not in_network or value:
                    raise ValueError("Touchstone [End] requires network data and no argument")
                ended, in_network = True, False
                continue
            if in_network:
                raise ValueError(f"Unsupported section [{key}] inside network data")
            allowed = {
                "version",
                "number of ports",
                "number of frequencies",
                "reference",
                "matrix format",
                "two-port data order",
                "network data",
                "number of noise frequencies",
            }
            if key not in allowed:
                raise ValueError(f"Unsupported Touchstone 2.0 keyword [{key}]")
            if key in declarations:
                raise ValueError(f"Duplicate Touchstone keyword [{key}]")
            declarations[key] = value
            if key == "network data":
                if value:
                    raise ValueError("[Network Data] takes no argument")
                in_network = True
            reference_continuation = key == "reference"
        elif line.startswith("#"):
            if in_network or options:
                raise ValueError("Duplicate or late Touchstone option line")
            options.append(line)
            reference_continuation = False
        elif in_network:
            network_lines.append(line)
        elif reference_continuation:
            declarations["reference"] += " " + line
        else:
            raise ValueError(f"Line {line_number}: data outside Touchstone network section")
    if declarations.get("version") != "2.0" or not ended:
        raise ValueError("Touchstone 2.0 requires [Version] 2.0, [Network Data] and [End]")
    try:
        nports = int(declarations["number of ports"])
        count = int(declarations["number of frequencies"])
    except (KeyError, ValueError) as exc:
        raise ValueError("Touchstone 2.0 requires integer port and frequency counts") from exc
    if not 1 <= nports <= 9 or not 1 <= count <= MAX_FREQUENCIES:
        raise ValueError("Touchstone 2.0 supports 1-9 ports and 1-100000 frequencies")
    extension = re.search(r"\.s(\d+)p$", filename, re.I)
    if (extension and int(extension[1]) != nports) or (
        extension is None and not filename.lower().endswith(".ts")
    ):
        raise ValueError("Filename port count/extension disagrees with Touchstone 2.0 declarations")
    if declarations.get("matrix format", "full").lower() != "full":
        raise ValueError("Touchstone 2.0 triangular matrices require separate qualification")
    if declarations.get("number of noise frequencies", "0") != "0":
        raise ValueError("Touchstone noise data requires separate qualification")
    if nports == 2 and "two-port data order" not in declarations:
        raise ValueError("Touchstone 2.0 two-port data requires [Two-Port Data Order]")
    order = declarations.get("two-port data order", "21_12").lower()
    if order not in ("21_12", "12_21") or (nports != 2 and "two-port data order" in declarations):
        raise ValueError("Invalid two-port data order")
    option = options[0] if options else "# GHz S MA R 50"
    # Reuse the qualified numeric parser; n>2 is serialized row-major per Touchstone.
    data = parse_touchstone(
        option + "\n" + "\n".join(network_lines),
        f"internal.s{nports}p",
        dataset_tag if dataset_tag is not None else filename.rsplit(".", 1)[0],
    )
    if len(data.freq_ghz) != count:
        raise ValueError("Touchstone declared frequency count does not match network records")
    refs_text = declarations.get("reference")
    try:
        references = (
            tuple(float(value) for value in refs_text.split())
            if refs_text is not None
            else (data.z0,) * nports
        )
    except ValueError as exc:
        raise ValueError("Invalid per-port reference impedance") from exc
    if len(references) != nports or any(
        not math.isfinite(value) or value <= 0 for value in references
    ):
        raise ValueError("[Reference] requires one positive finite impedance per port")
    points = data.points
    if nports == 2 and order == "12_21":
        reordered: list[TouchstonePoint] = []
        for offset in range(0, len(points), 4):
            record = points[offset : offset + 4]
            reordered.extend(
                (
                    record[0],
                    record[2].model_copy(update={"param": "S21"}),
                    record[1].model_copy(update={"param": "S12"}),
                    record[3],
                )
            )
        points = tuple(reordered)
    return data.model_copy(
        update={
            "filename": filename,
            "version": "2.0",
            "reference_ohms": references,
            "z0": references[0],
            "points": points,
            "comments": tuple(comments),
        }
    )
