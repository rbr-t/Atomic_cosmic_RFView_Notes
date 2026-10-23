"""Explicit fundamental-only SPL power-sweep-plan dialect; no alias precedence."""

import math
import re

from pydantic import BaseModel, ConfigDict

from rfview.domain.loadpull import (
    MAX_LOADPULL_BYTES,
    MAX_LOADPULL_POINTS,
    LoadPullData,
    LoadPullPoint,
    _frequency,
    _header,
    _row,
    normalise_loadpull_row,
)

MAX_SPL_PLAN_VIEW_POINTS = 2_000
MAX_SPL_PLAN_SECTIONS = 1_000
_COLUMNS = _header(
    "VALID GAMMA_SRC1 GAMMA_LD1 FREQ PIN_AVAIL_DBM POUT_DBM GT_DB IQ_OUT_MA "
    "VQ_IN_V VOUT_V IOUT_MA VIN_V EFF_% EFF_COL PDIS POUTW",
    expand_gamma=True,
)
_MAPPING = {
    "GAMMA_SRC1_RE": "GS_R",
    "GAMMA_SRC1_IM": "GS_I",
    "GAMMA_LD1_RE": "GL_R",
    "GAMMA_LD1_IM": "GL_I",
    "FREQ": "FREQ_GHZ",
    "PIN_AVAIL_DBM": "PIN_DBM",
    "POUT_DBM": "POUT_DBM",
    "GT_DB": "GAIN_DB",
    "VOUT_V": "VDC_V",
    "IOUT_MA": "IDC(MA)",
    "EFF_COL": "DE_PCT",
}


class SplPlanSection(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    index: int
    frequency_ghz: float
    slots: int
    valid_rows: int
    invalid_rows: int


class SplPlanImport(BaseModel):
    model_config = ConfigDict(frozen=True)

    dataset: LoadPullData
    sections: tuple[SplPlanSection, ...]


def parse_spl_plan(text: str, filename: str, *, section_index: int = 1) -> SplPlanImport:
    """Validate all declared sections and retain every valid row of the selected section."""
    if len(text.encode("utf-8")) > MAX_LOADPULL_BYTES:
        raise ValueError("SPL plan exceeds the 5 MiB limit")
    if isinstance(section_index, bool) or not isinstance(section_index, int) or section_index < 1:
        raise ValueError("SPL plan section index must be a positive integer")
    metadata: dict[str, str] = {}
    declarations: dict[str, int] = {}
    table: list[tuple[float, int]] = []
    sections: list[SplPlanSection] = []
    points: list[LoadPullPoint] = []
    warnings: dict[str, None] = {}
    variables: list[str] = []
    columns: list[str] | None = None
    frequency: float | None = None
    harmonics_seen = False
    slots = valid = 0

    def finish_section() -> None:
        if frequency is None:
            return
        if columns is None or slots != table[len(sections)][1]:
            raise ValueError(
                f"SPL plan section {len(sections) + 1}: missing header or slot count mismatch "
                f"({slots}/{table[len(sections)][1]})"
            )
        sections.append(
            SplPlanSection(
                index=len(sections) + 1,
                frequency_ghz=frequency,
                slots=slots,
                valid_rows=valid,
                invalid_rows=slots - valid,
            )
        )

    for line_number, original in enumerate(text.lstrip("\ufeff").splitlines(), 1):
        line = original.strip()
        if not line:
            continue
        if line.startswith(("!", "#")):
            metadata[f"line_{line_number}"] = line
            continue
        section = re.fullmatch(r"Freq\s*=\s*(.+)", line, re.I)
        if section is not None:
            finish_section()
            if not table or len(table) != declarations.get("frequencies"):
                raise ValueError("SPL plan frequency table does not match the declared count")
            if (
                declarations.get("variables") != 2
                or variables != ["F1 LOAD GAMMA|", "PIN_AVAIL|DBM"]
                or declarations.get("user_params") != 3
                or metadata.get("user_names") != "EFF_COL PDIS POUTW"
                or metadata.get("user_units") != "% W W"
            ):
                raise ValueError("SPL plan requires the qualified two-variable measurement profile")
            if len(sections) >= len(table):
                raise ValueError("SPL plan has more sections than declared frequencies")
            frequency = _frequency(section[1])
            if frequency <= 0 or not math.isclose(
                frequency, table[len(sections)][0], rel_tol=1e-9, abs_tol=1e-12
            ):
                raise ValueError("SPL plan section frequency disagrees with the frequency table")
            slots = valid = 0
            columns, harmonics_seen = None, False
            continue
        if frequency is None:
            count = re.fullmatch(
                r"(Number of Frequencies|Number of Variables|User params)\s*=\s*(\d+)",
                line,
                re.I,
            )
            if count is not None:
                key = {
                    "number of frequencies": "frequencies",
                    "number of variables": "variables",
                    "user params": "user_params",
                }[count[1].lower()]
                if key in declarations or int(count[2]) < 1:
                    raise ValueError(f"SPL plan line {line_number}: duplicate/invalid declaration")
                declarations[key] = int(count[2])
                if key == "frequencies" and declarations[key] > MAX_SPL_PLAN_SECTIONS:
                    raise ValueError("SPL plan exceeds the 1000 frequency-section limit")
                continue
            variable = re.fullmatch(r"VAR\s*=\s*<([^>]+)>,\s*Units\s*=\s*<([^>]*)>", line, re.I)
            if variable is not None:
                variables.append(f"{variable[1].upper()}|{variable[2].upper()}")
                continue
            user = re.fullmatch(r"User (names|units)\s*:\s*(.+)", line, re.I)
            if user is not None:
                key = f"user_{user[1].lower()}"
                if key in metadata:
                    raise ValueError(f"SPL plan line {line_number}: duplicate user descriptor")
                metadata[key] = " ".join(user[2].upper().split())
                continue
            tokens = line.split()
            if len(tokens) == 3 and all(re.fullmatch(r"\d+", v) for v in tokens[1:]):
                if len(table) >= declarations.get("frequencies", 0):
                    raise ValueError("SPL plan has more table rows than declared frequencies")
                freq = _frequency(tokens[0])
                count_slots = int(tokens[1]) * int(tokens[2])
                if (
                    freq <= 0
                    or count_slots < 1
                    or any(math.isclose(freq, old, rel_tol=1e-9, abs_tol=1e-12) for old, _ in table)
                ):
                    raise ValueError("SPL plan has duplicate/invalid frequency table rows")
                table.append((freq, count_slots))
                if sum(count for _, count in table) > MAX_LOADPULL_POINTS:
                    raise ValueError("SPL plan exceeds the 100000 source-slot limit")
                continue
            raise ValueError(f"SPL plan line {line_number}: unrecognized preamble")
        if not harmonics_seen:
            if re.fullmatch(r"num_src_harmonics\s*=\s*1,\s*num_ld_harmonics\s*=\s*1", line, re.I):
                harmonics_seen = True
                continue
            raise ValueError(
                f"SPL plan line {line_number}: requires fundamental-only source/load harmonics"
            )
        if columns is None:
            columns = _header(line, expand_gamma=True)
            if set(columns) != set(_COLUMNS):
                raise ValueError(f"SPL plan line {line_number}: unsupported measurement columns")
            continue
        slots += 1
        if slots > table[len(sections)][1]:
            raise ValueError(f"SPL plan line {line_number}: too many section slots")
        if line == "0":
            continue
        raw = _row(columns, line.split(), line_number)
        if any(value is None for value in raw.values()):
            raise ValueError(f"SPL plan line {line_number}: missing numeric measurement")
        if raw["VALID"] not in (0, 1):
            raise ValueError(f"SPL plan line {line_number}: VALID must be 0 or 1")
        if raw["FREQ"] is None or not math.isclose(
            raw["FREQ"], frequency, rel_tol=1e-9, abs_tol=1e-12
        ):
            raise ValueError(f"SPL plan line {line_number}: row/section frequency mismatch")
        if raw["VALID"] == 0:
            continue
        valid += 1
        row_warnings: dict[str, None] = {}
        try:
            point = normalise_loadpull_row(
                {target: raw[source] for source, target in _MAPPING.items()},
                frequency,
                "percent",
                row_warnings,
                slots,
            )
        except OverflowError as exc:
            raise ValueError(
                f"SPL plan line {line_number}: calculation exceeds numeric range"
            ) from exc
        if len(sections) + 1 != section_index:
            continue
        if len(points) >= MAX_SPL_PLAN_VIEW_POINTS:
            raise ValueError("Selected SPL section exceeds 2000 viewer points; no rows dropped")
        warnings.update(row_warnings)
        points.append(
            point.model_copy(
                update={
                    "extra": {
                        **{f"source.{key.lower()}": value for key, value in raw.items()},
                        "source.slot_index": float(slots),
                        "source.section_index": float(section_index),
                    },
                }
            )
        )
    finish_section()
    if not sections or len(sections) != len(table):
        raise ValueError("SPL plan is missing declared frequency sections")
    if section_index > len(sections):
        raise ValueError(f"Choose an available SPL plan section (1-{len(sections)})")
    if not points:
        raise ValueError("Selected SPL plan section contains no valid measurement rows")
    selected = sections[section_index - 1]
    warnings.update(
        dict.fromkeys(
            (
                "SPL plan mapping: Eff_col is drain efficiency (%); PAE is derived from "
                "Pin_avail_dBm, Pout_dBm and Vout_v*Iout_mA/1000. Eff_%, Pdis, PoutW, "
                "quiescent current and gate bias remain separate source columns.",
                f"Selected section {section_index}/{len(sections)} at "
                f"{selected.frequency_ghz:.12g} GHz: "
                f"{selected.valid_rows} valid measurements, {selected.invalid_rows} VALID=0 slots "
                "explicitly excluded. All sections validated; "
                "export contains selected valid rows only.",
                "Gamma is the source file's gamma_src1/gamma_ld1 Cartesian pair. "
                "No reference-plane transformation or calibration is inferred. Exact measured "
                "Pin/source Gamma/bias grouping is retained; "
                "no rounding to fabricate contour sweeps.",
            )
        )
    )
    metadata.update(
        selected_section=str(section_index),
        total_sections=str(len(sections)),
        frequency_ghz=f"{selected.frequency_ghz:.17g}",
        selected_slots=str(selected.slots),
        selected_invalid_rows=str(selected.invalid_rows),
        total_source_slots=str(sum(s.slots for s in sections)),
        total_valid_rows=str(sum(s.valid_rows for s in sections)),
        total_invalid_rows=str(sum(s.invalid_rows for s in sections)),
        mapping="; ".join(f"{source}->{target}" for source, target in _MAPPING.items()),
    )
    return SplPlanImport(
        dataset=LoadPullData(
            filename=re.split(r"[\\/]", filename)[-1],
            format="spl_plan",
            points=tuple(points),
            metadata=metadata,
            warnings=tuple(warnings),
        ),
        sections=tuple(sections),
    )
