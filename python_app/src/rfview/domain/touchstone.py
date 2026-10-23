"""Bounded Touchstone S-parameters with explicit v2 matrix, mode and noise semantics."""

import math
import re
from typing import Literal, NamedTuple

from pydantic import BaseModel, ConfigDict, Field

from rfview.domain.network_parameters import s_to_abcd, s_to_h, s_to_t, s_to_y, s_to_z

MAX_TOUCHSTONE_BYTES = 5 * 1024 * 1024
MAX_FREQUENCIES = 100_000


class NoisePoint(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    freq_ghz: float = Field(ge=0)
    minimum_nf_db: float
    gamma_opt_mag: float = Field(ge=0)
    gamma_opt_deg: float
    resistance_ohm: float = Field(ge=0)


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
    mixed_mode_order: tuple[str, ...] = ()
    noise: tuple[NoisePoint, ...] = ()
    noise_reference_ohm: float | None = None

    def port_references(self) -> tuple[float, ...]:
        references = self.reference_ohms or (self.z0,) * self.nports
        if not self.mixed_mode_order:
            return references
        return tuple(
            references[int(mode[1]) - 1] * (2 if mode[0] == "D" else 0.5 if mode[0] == "C" else 1)
            for mode in self.mixed_mode_order
        )


class ConvertedParameter(NamedTuple):
    freq_ghz: float
    parameter: str
    unit: str
    value: complex


def transform_network_basis(
    network: TouchstoneData,
    mixed_mode_order: tuple[str, ...] = (),
) -> TouchstoneData:
    """Power-wave orthonormal basis change; physical paired references must be equal."""
    nports = network.nports
    references = network.reference_ohms or (network.z0,) * nports
    target_modes = (
        _mixed_modes(" ".join(mixed_mode_order), nports, references) if mixed_mode_order else ()
    )
    source_modes = (
        _mixed_modes(" ".join(network.mixed_mode_order), nports, references)
        if network.mixed_mode_order
        else ()
    )
    if source_modes == target_modes:
        return network
    if network.noise:
        raise ValueError("Noise-parameter basis transformation is not implemented; source retained")

    def basis(modes: tuple[str, ...]) -> list[list[float]]:
        if not modes:
            return [[float(r == c) for c in range(nports)] for r in range(nports)]
        rows = []
        for mode in modes:
            row = [0.0] * nports
            if mode[0] == "S":
                row[int(mode[1:]) - 1] = 1
            else:
                a, b = (int(port) - 1 for port in mode[1:].split(","))
                row[a] = 1 / math.sqrt(2)
                row[b] = (-1 if mode[0] == "D" else 1) / math.sqrt(2)
            rows.append(row)
        return rows

    source, target = basis(source_modes), basis(target_modes)
    rotation = [
        [sum(target[r][k] * source[c][k] for k in range(nports)) for c in range(nports)]
        for r in range(nports)
    ]
    if len(network.points) != len(network.freq_ghz) * nports**2:
        raise ValueError("Basis transformation requires complete network matrices")
    points = []
    order = (
        [(0, 0), (1, 0), (0, 1), (1, 1)]
        if nports == 2
        else [(r, c) for r in range(nports) for c in range(nports)]
    )
    for offset, frequency in enumerate(network.freq_ghz):
        entries = {
            p.param: complex(p.real, p.imag)
            for p in network.points[offset * nports**2 : (offset + 1) * nports**2]
        }
        expected = {f"S{r + 1}{c + 1}" for r in range(nports) for c in range(nports)}
        if entries.keys() != expected:
            raise ValueError("Basis transformation requires distinct complete Sij entries")
        intermediate = [
            [
                sum(rotation[r][k] * entries[f"S{k + 1}{c + 1}"] for k in range(nports))
                for c in range(nports)
            ]
            for r in range(nports)
        ]
        for r, c in order:
            value = sum(intermediate[r][k] * rotation[c][k] for k in range(nports))
            magnitude = abs(value)
            if not math.isfinite(magnitude):
                raise ValueError(f"Basis transformation exceeds numeric range at {frequency:g} GHz")
            points.append(
                TouchstonePoint(
                    freq_ghz=frequency,
                    param=f"S{r + 1}{c + 1}",
                    real=value.real,
                    imag=value.imag,
                    mag_linear=magnitude,
                    mag_db=20 * math.log10(max(magnitude, 1e-15)),
                    phase_deg=math.degrees(math.atan2(value.imag, value.real)),
                    dataset_tag=network.dataset_tag,
                )
            )
    return network.model_copy(
        update={
            "points": tuple(points),
            "mixed_mode_order": target_modes,
            "version": "2.0",
            "data_format": "ri",
            "reference_ohms": references,
            "comments": (
                *network.comments,
                "! RFView explicit orthonormal power-wave basis transformation",
            ),
        }
    )


def converted_parameters(
    network: TouchstoneData, representation: str
) -> tuple[ConvertedParameter, ...]:
    if representation not in ("Z", "Y", "h", "ABCD", "T"):
        raise ValueError("Converted export/view requires Z, Y, h, ABCD or T")
    if network.nports != 2:
        raise ValueError("Parameter conversion requires a two-port dataset")
    if network.mixed_mode_order:
        raise ValueError(
            "Mixed-mode data is preserved in its declared basis; no single-ended conversion"
        )
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
    export_v2 = (
        network.version == "2.0"
        or len(set(references)) != 1
        or bool(network.noise)
        or bool(network.mixed_mode_order)
    )
    option_reference = network.noise_reference_ohm if network.noise else references[0]
    if option_reference is None or not math.isfinite(option_reference) or option_reference <= 0:
        raise ValueError("Noise data requires a positive finite option-line reference impedance")
    if export_v2:
        lines.extend(
            (
                "[Version] 2.0",
                f"# GHz S RI R {option_reference:.17g}",
                f"[Number of Ports] {network.nports}",
                f"[Number of Frequencies] {len(network.freq_ghz)}",
                "[Reference] " + " ".join(f"{value:.17g}" for value in references),
                "[Matrix Format] Full",
            )
        )
        if network.nports == 2:
            lines.append("[Two-Port Data Order] 21_12")
        if network.mixed_mode_order:
            lines.append("[Mixed-Mode Order] " + " ".join(network.mixed_mode_order))
        if network.noise:
            lines.append(f"[Number of Noise Frequencies] {len(network.noise)}")
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
        if not export_v2 and network.nports >= 3:
            for row in range(network.nports):
                row_tokens = tokens[
                    1 + row * 2 * network.nports : 1 + (row + 1) * 2 * network.nports
                ]
                for start in range(0, len(row_tokens), 8):
                    prefix = [tokens[0]] if row == start == 0 else []
                    lines.append(" ".join(prefix + row_tokens[start : start + 8]))
        else:
            lines.append(" ".join(tokens))
    if network.noise:
        lines.append("[Noise Data]")
        lines.extend(
            " ".join(
                f"{value:.17g}"
                for value in (
                    point.freq_ghz,
                    point.minimum_nf_db,
                    point.gamma_opt_mag,
                    point.gamma_opt_deg,
                    point.resistance_ohm,
                )
            )
            for point in network.noise
        )
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
    noise_lines: list[str] = []
    in_noise = False
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
        tokens = line.split()
        if in_noise:
            noise_lines.append(line)
            continue
        if nports == 2 and numbers and len(numbers) % 9 == 0 and len(tokens) == 5:
            try:
                candidate = float(tokens[0].replace("D", "E").replace("d", "e"))
            except ValueError as exc:
                raise ValueError(f"Line {line_number}: invalid noise frequency") from exc
            if candidate <= numbers[-9]:
                in_noise = True
                noise_lines.append(line)
                continue
        for token in tokens:
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
    noise = _noise_points(
        noise_lines,
        str(len(noise_lines)) if noise_lines else None,
        nports,
        unit,
        frequencies[-1],
        bool(noise_lines),
    )
    normalized_noise: list[NoisePoint] = []
    for point in noise:
        resistance = point.resistance_ohm * z0
        if not math.isfinite(resistance):
            raise ValueError("Touchstone 1.x noise resistance exceeds numeric range")
        normalized_noise.append(point.model_copy(update={"resistance_ohm": resistance}))
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
        noise=tuple(normalized_noise),
        noise_reference_ohm=z0 if noise else None,
    )


def _parse_touchstone_v2(text: str, filename: str, dataset_tag: str | None) -> TouchstoneData:
    declarations: dict[str, str] = {}
    options: list[str] = []
    network_lines: list[str] = []
    comments: list[str] = []
    noise_lines: list[str] = []
    in_network = ended = False
    in_noise = noise_seen = False
    continuation: str | None = None
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
            continuation = None
            key, value = keyword[1].lower(), keyword[2].strip()
            if key == "end":
                if not (in_network or in_noise) or value:
                    raise ValueError("Touchstone [End] requires network data and no argument")
                ended, in_network, in_noise = True, False, False
                continue
            if key == "noise data":
                if not in_network or in_noise or value:
                    raise ValueError("[Noise Data] requires preceding network data and no argument")
                in_network, in_noise = False, True
                noise_seen = True
                continue
            if in_network or in_noise:
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
                "mixed-mode order",
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
            continuation = key if key in ("reference", "mixed-mode order") else None
        elif line.startswith("#"):
            if in_network or in_noise or options:
                raise ValueError("Duplicate or late Touchstone option line")
            options.append(line)
            continuation = None
        elif in_network:
            network_lines.append(line)
        elif in_noise:
            noise_lines.append(line)
        elif continuation is not None:
            declarations[continuation] += " " + line
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
    matrix_format = declarations.get("matrix format", "full").lower()
    if matrix_format not in ("full", "lower", "upper"):
        raise ValueError("Matrix Format must be Full, Lower or Upper")
    if nports == 2 and "two-port data order" not in declarations:
        raise ValueError("Touchstone 2.0 two-port data requires [Two-Port Data Order]")
    order = declarations.get("two-port data order", "21_12").lower()
    if order not in ("21_12", "12_21") or (nports != 2 and "two-port data order" in declarations):
        raise ValueError("Invalid two-port data order")
    option = options[0] if options else "# GHz S MA R 50"
    if matrix_format != "full":
        network_lines = _expand_triangular(network_lines, nports, count, matrix_format)
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
    modes = _mixed_modes(declarations.get("mixed-mode order"), nports, references)
    noise = _noise_points(
        noise_lines,
        declarations.get("number of noise frequencies"),
        nports,
        data.freq_unit,
        data.freq_ghz[-1],
        noise_seen,
    )
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
            "mixed_mode_order": modes,
            "noise": noise,
            "noise_reference_ohm": data.z0 if noise else None,
        }
    )


def _expand_triangular(lines: list[str], nports: int, count: int, matrix_format: str) -> list[str]:
    numbers = " ".join(lines).split()
    indices = [
        (r, c)
        for r in range(nports)
        for c in range(nports)
        if (c <= r if matrix_format == "lower" else c >= r)
    ]
    width = 1 + 2 * len(indices)
    if len(numbers) != count * width:
        raise ValueError("Triangular matrix record count/width disagrees with declarations")
    expanded = []
    order = (
        [(0, 0), (1, 0), (0, 1), (1, 1)]
        if nports == 2
        else [(r, c) for r in range(nports) for c in range(nports)]
    )
    for offset in range(0, len(numbers), width):
        matrix: dict[tuple[int, int], list[str]] = {}
        for index, (r, c) in enumerate(indices):
            pair = numbers[offset + 1 + 2 * index : offset + 3 + 2 * index]
            matrix[r, c] = matrix[c, r] = pair  # Symmetric, not conjugate symmetric.
        expanded.append(" ".join([numbers[offset], *(v for rc in order for v in matrix[rc])]))
    return expanded


def _mixed_modes(raw: str | None, nports: int, references: tuple[float, ...]) -> tuple[str, ...]:
    if raw is None:
        return ()
    raw = re.sub(r"\s*,\s*", ",", raw.upper())
    modes = tuple(raw.split())
    if len(modes) != nports or len(set(modes)) != nports:
        raise ValueError("Mixed-Mode Order requires one distinct descriptor per matrix dimension")
    used: set[int] = set()
    pairs: dict[tuple[int, int], set[str]] = {}
    for mode in modes:
        match = re.fullmatch(r"S([1-9])|([DC])([1-9]),([1-9])", mode)
        if match is None:
            raise ValueError("Invalid Mixed-Mode Order descriptor")
        if match[1] is not None:
            port = int(match[1])
            if port > nports or port in used:
                raise ValueError("Mixed-Mode Order overlaps or exceeds available ports")
            used.add(port)
        else:
            a, b = int(match[3]), int(match[4])
            if a == b or max(a, b) > nports:
                raise ValueError("Mixed-mode pairs require distinct available ports")
            pair = (a, b)
            if pair not in pairs:
                if a in used or b in used:
                    raise ValueError("Mixed-Mode Order has overlapping or reversed pairs")
                used.update((a, b))
                pairs[pair] = set()
            pairs[pair].add(match[2])
            if references[a - 1] != references[b - 1]:
                raise ValueError(
                    "Mixed-mode pair must have equal single-ended reference impedances"
                )
    if used != set(range(1, nports + 1)) or any(kinds != {"D", "C"} for kinds in pairs.values()):
        raise ValueError("Mixed-Mode Order must cover all ports with matched D/C pairs")
    return modes


def _noise_points(
    lines: list[str],
    declared: str | None,
    nports: int,
    unit: str,
    max_frequency: float,
    section_seen: bool,
) -> tuple[NoisePoint, ...]:
    if declared is None:
        if section_seen:
            raise ValueError("Noise data requires Number of Noise Frequencies")
        return ()
    try:
        count = int(declared)
    except ValueError as exc:
        raise ValueError("Invalid noise frequency count") from exc
    if nports != 2 or not 1 <= count <= MAX_FREQUENCIES or not section_seen or len(lines) != count:
        raise ValueError("Noise data requires two ports and matching positive declared row count")
    scale = {"hz": 1e-9, "khz": 1e-6, "mhz": 1e-3, "ghz": 1}[unit]
    result: list[NoisePoint] = []
    for line in lines:
        try:
            values = [float(token.replace("D", "E").replace("d", "e")) for token in line.split()]
        except ValueError as exc:
            raise ValueError("Invalid numeric noise data") from exc
        if len(values) != 5 or not all(math.isfinite(value) for value in values):
            raise ValueError("Noise data requires five finite values per row")
        point = NoisePoint(
            freq_ghz=values[0] * scale,
            minimum_nf_db=values[1],
            gamma_opt_mag=values[2],
            gamma_opt_deg=values[3],
            resistance_ohm=values[4],
        )
        if result and point.freq_ghz <= result[-1].freq_ghz:
            raise ValueError("Noise frequencies must be strictly increasing")
        result.append(point)
    if result[0].freq_ghz > max_frequency:
        raise ValueError("First noise frequency must not exceed highest network frequency")
    return tuple(result)
