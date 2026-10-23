"""Streaming ALPS typed Sweep blocks with explicit measurement-plane mappings."""

import csv
import math
import re
from collections.abc import Iterable
from typing import Literal

from pydantic import BaseModel, ConfigDict

from rfview.domain.loadpull import LoadPullData, LoadPullPoint, normalise_loadpull_row

MAX_ALPS_BYTES = 64 * 1024 * 1024
MAX_ALPS_ROWS = 200_000
MAX_ALPS_BLOCKS = 5_000
MAX_ALPS_BLOCK_ROWS = 2_000
ALPS_PLANES = {
    "dut": "DUT Gamma (GLRE/GLIM, GSRE/GSIM)",
    "instrument": "Instrument Gamma (gamma_ld1/src1_re/im)",
}
AlpsPlane = Literal["dut", "instrument"]


class AlpsBlock(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    index: int
    rows: int
    variables: dict[str, float]


class AlpsImport(BaseModel):
    model_config = ConfigDict(frozen=True, allow_inf_nan=False)

    dataset: LoadPullData
    blocks: tuple[AlpsBlock, ...]
    total_rows: int


def _numeric(token: str, line_number: int) -> float:
    try:
        value = float(token.replace("D", "E").replace("d", "e"))
    except ValueError as exc:
        raise ValueError(f"ALPS line {line_number}: invalid numeric field") from exc
    if not math.isfinite(value):
        raise ValueError(f"ALPS line {line_number}: nonfinite numeric field")
    return value


def read_alps_lines(
    lines: Iterable[str],
    filename: str,
    *,
    plane: AlpsPlane,
    block_index: int,
    backoff_db: float | None = None,
) -> AlpsImport:
    """Validate the entire bounded stream, retaining only the explicitly selected block."""
    if plane not in ALPS_PLANES:
        raise ValueError("Choose DUT or instrument Gamma mapping explicitly")
    if isinstance(block_index, bool) or not isinstance(block_index, int) or block_index < 1:
        raise ValueError("ALPS block index must be a positive integer")
    if backoff_db is not None and (isinstance(backoff_db, bool) or not math.isfinite(backoff_db)):
        raise ValueError("ALPS backoff must be a finite number of dB")
    mapping = {
        "PIN_AVAIL_DBM": "PIN_DBM",
        "POUT_DBM": "POUT_DBM",
        "GT_DB": "GAIN_DB",
        "FREQ": "FREQ_GHZ",
        "EFF_COL": "DE_PCT",
        "VOUT_V": "VDC_V",
        "IOUT_MA": "IDC(MA)",
    }
    mapping.update(
        {
            "GLRE": "GL_R",
            "GLIM": "GL_I",
            "GSRE": "GS_R",
            "GSIM": "GS_I",
        }
        if plane == "dut"
        else {
            "GAMMA_LD1_RE": "GL_R",
            "GAMMA_LD1_IM": "GL_I",
            "GAMMA_SRC1_RE": "GS_R",
            "GAMMA_SRC1_IM": "GS_I",
        }
    )
    blocks: list[AlpsBlock] = []
    points: list[LoadPullPoint] = []
    variables: dict[str, float] = {}
    selected_variables: dict[str, float] = {}
    columns: list[tuple[str, str]] | None = None
    active = False
    rows = total_rows = total_bytes = 0
    warnings: dict[str, None] = {}
    for line_number, original in enumerate(lines, 1):
        total_bytes += len(original.encode("utf-8"))
        if total_bytes > MAX_ALPS_BYTES or len(original) > 1024 * 1024:
            raise ValueError("ALPS input exceeds the 64 MiB file / 1 MiB line limit")
        line = original.lstrip("\ufeff").strip()
        if not line or line.startswith(("!", "#")):
            continue
        upper = line.upper()
        if upper == "BEGIN SWEEP":
            if active:
                raise ValueError(f"ALPS line {line_number}: nested Sweep")
            if len(blocks) >= MAX_ALPS_BLOCKS:
                raise ValueError("ALPS exceeds 5000 blocks")
            active, columns, rows = True, None, 0
            if backoff_db is None and len(blocks) + 1 == block_index:
                selected_variables = dict(variables)
            continue
        if upper in ("END", "END SWEEP"):
            if not active or columns is None or not rows:
                raise ValueError(f"ALPS line {line_number}: unexpected or empty END")
            blocks.append(AlpsBlock(index=len(blocks) + 1, rows=rows, variables=dict(variables)))
            active = False
            variables = {}
            continue
        if upper.startswith("VAR "):
            match = re.fullmatch(r"VAR\s+(\w+)\(real\)\s*=\s*(\S+)", line, re.I)
            if active or match is None:
                raise ValueError(f"ALPS line {line_number}: invalid/out-of-place VAR")
            key = match[1].upper()
            if key in variables:
                raise ValueError(f"ALPS line {line_number}: duplicate VAR")
            variables[key] = _numeric(match[2], line_number)
            continue
        if not active:
            raise ValueError(f"ALPS line {line_number}: content outside a Sweep")
        if columns is None:
            tokens = line.lstrip("%").split()
            parsed = [
                re.fullmatch(r"(\w+)\((real|integer|string)\)", token, re.I) for token in tokens
            ]
            if not tokens or any(match is None for match in parsed):
                raise ValueError(f"ALPS line {line_number}: expected typed column header")
            columns = [
                (match[1].upper(), match[2].lower()) for match in parsed if match is not None
            ]
            names = [name for name, _ in columns]
            if len(set(names)) != len(names) or not mapping.keys() <= set(names):
                raise ValueError(f"ALPS line {line_number}: duplicate or missing mapped columns")
            if backoff_db is not None and "BO" not in names:
                raise ValueError("ALPS fixed-backoff selection requires the BO column")
            if [kind for _, kind in columns].count("string") != 1 or columns[-1][1] != "string":
                raise ValueError("ALPS requires exactly one trailing quoted string column")
            continue
        numeric_count = len(columns) - 1
        tokens = line.split(maxsplit=numeric_count)
        if len(tokens) != len(columns) or re.fullmatch(r'"(?:[^"]|"")*"', tokens[-1]) is None:
            raise ValueError(f"ALPS line {line_number}: ragged row or invalid quoted string")
        numeric = {
            name: _numeric(token, line_number)
            for (name, _), token in zip(columns[:-1], tokens[:-1], strict=True)
        }
        for name, kind in columns[:-1]:
            if kind == "integer" and not numeric[name].is_integer():
                raise ValueError(f"ALPS line {line_number}: noninteger field {name}")
        rows += 1
        total_rows += 1
        if total_rows > MAX_ALPS_ROWS:
            raise ValueError("ALPS exceeds 200000 measurement rows")
        selected_row = (
            math.isclose(numeric["BO"], backoff_db, rel_tol=0, abs_tol=1e-8)
            if backoff_db is not None
            else len(blocks) + 1 == block_index
        )
        if not selected_row:
            continue
        if len(points) >= MAX_ALPS_BLOCK_ROWS:
            raise ValueError("Selected ALPS subset exceeds 2000 viewer points; no rows dropped")
        try:
            point = normalise_loadpull_row(
                {target: numeric[source] for source, target in mapping.items()},
                None,
                "percent",
                warnings,
                rows,
            )
        except OverflowError as exc:
            raise ValueError(f"ALPS line {line_number}: calculation exceeds numeric range") from exc
        source_string = next(csv.reader([tokens[-1]], strict=True))[0]
        points.append(
            point.model_copy(
                update={
                    "extra": {
                        **{f"source.{key.lower()}": value for key, value in numeric.items()},
                        **{f"var.{key.lower()}": value for key, value in variables.items()},
                        "source.block_index": float(len(blocks) + 1),
                    },
                    "source_strings": {columns[-1][0].lower(): source_string},
                }
            )
        )
    if active:
        raise ValueError("Unclosed ALPS Sweep")
    if variables:
        raise ValueError("ALPS VAR declarations have no following Sweep")
    if backoff_db is not None and not points:
        raise ValueError(f"No ALPS rows match BO={backoff_db:.12g} dB (tolerance 1e-8 dB)")
    if not blocks or (backoff_db is None and block_index > len(blocks)) or not points:
        raise ValueError(f"Choose an available ALPS block (1-{len(blocks)})")
    selection = (
        f"BO={backoff_db:.12g} dB across blocks (tolerance 1e-8 dB)"
        if backoff_db is not None
        else f"block {block_index}/{len(blocks)}"
    )
    warnings.update(
        dict.fromkeys(
            (
                "ALPS uses an explicit column mapping, not alias precedence or compression fields.",
                "Eff_col is entered drain efficiency (%); PAE is derived from Pin/Pout "
                "and Vout*Iout. Pdis, BO, quiescent current and compression columns "
                "are preserved, not treated as PDC/Pin/PAE.",
                f"Only {selection} is loaded ({len(points)}/{total_rows} rows). "
                "All source rows were structurally/numerically validated; no decimation. "
                "Export contains this selected subset, not the full file.",
                "Gamma reference plane is explicitly selected; confirm calibration/"
                "reference impedance "
                "before using these values in engineering calculations.",
            )
        )
    )
    return AlpsImport(
        dataset=LoadPullData(
            filename=re.split(r"[\\/]", filename)[-1],
            format="alps_mdf",
            points=tuple(points),
            metadata={
                "gamma_plane": ALPS_PLANES[plane],
                "selected_block": str(block_index),
                "selection": selection,
                "selection_kind": "backoff" if backoff_db is not None else "block",
                **({"backoff_db": f"{backoff_db:.17g}"} if backoff_db is not None else {}),
                "total_blocks": str(len(blocks)),
                "total_source_rows": str(total_rows),
                "mapping": "; ".join(f"{source}->{target}" for source, target in mapping.items()),
                **{f"VAR_{key}": f"{value:.17g}" for key, value in selected_variables.items()},
            },
            warnings=tuple(warnings),
        ),
        blocks=tuple(blocks),
        total_rows=total_rows,
    )
