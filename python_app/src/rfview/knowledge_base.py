"""Bounded, local-only reader and exact filter for the checked-in RF device KB."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Annotated
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

MAX_KB_FILE_BYTES = 8 * 1024 * 1024
MAX_KB_TOTAL_BYTES = 32 * 1024 * 1024
MAX_KB_DEVICES = 10_000
MAX_SEARCH_RESULTS = 200

NonEmptyString = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=240)
]


class DeviceRecord(BaseModel):
    model_config = ConfigDict(extra="allow", allow_inf_nan=False)

    device_id: NonEmptyString
    part_number: NonEmptyString
    manufacturer: NonEmptyString
    technology: NonEmptyString
    freq_min_mhz: float = Field(ge=0, strict=True, allow_inf_nan=False)
    freq_max_mhz: float = Field(ge=0, strict=True, allow_inf_nan=False)
    vdd_v: float | None = Field(default=None, ge=0, strict=True, allow_inf_nan=False)
    pout_w_cw: float | None = Field(default=None, ge=0, strict=True, allow_inf_nan=False)
    pout_w_pulse: float | None = Field(default=None, ge=0, strict=True, allow_inf_nan=False)
    gain_db: float | None = Field(default=None, strict=True, allow_inf_nan=False)
    drain_eff_pct: float | None = Field(
        default=None, ge=0, le=100, strict=True, allow_inf_nan=False
    )
    pae_pct: float | None = Field(default=None, ge=0, le=100, strict=True, allow_inf_nan=False)
    knowledge_source: str | None = None
    knowledge_confidence: str | None = None
    status: str | None = None
    datasheet_url: str | None = None
    notes: str | None = None

    @model_validator(mode="after")
    def validate_frequency_range(self) -> DeviceRecord:
        if self.freq_max_mhz < self.freq_min_mhz:
            raise ValueError("Maximum frequency must not be below minimum frequency")
        return self


class CatalogDevice(BaseModel):
    model_config = ConfigDict(extra="forbid")

    record: DeviceRecord
    source_file: str
    source_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")


class DeviceReference(BaseModel):
    """Provenance-only attachment; not a source of lineup calculation values."""

    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    device_id: NonEmptyString
    part_number: NonEmptyString
    manufacturer: NonEmptyString
    technology: NonEmptyString
    freq_min_mhz: float = Field(ge=0, strict=True)
    freq_max_mhz: float = Field(ge=0, strict=True)
    knowledge_source: str | None = Field(default=None, max_length=120)
    knowledge_confidence: str | None = Field(default=None, max_length=120)
    status: str | None = Field(default=None, max_length=120)
    datasheet_url: str | None = Field(default=None, max_length=2048)
    catalog_source_file: str = Field(pattern=r"^[A-Za-z0-9_.-]+/devices\.json$")
    catalog_source_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def validate_reference(self) -> DeviceReference:
        vendor = self.catalog_source_file.split("/", maxsplit=1)[0]
        if vendor in (".", ".."):
            raise ValueError("Catalog source path must remain within one vendor directory")
        if self.freq_max_mhz < self.freq_min_mhz:
            raise ValueError("Maximum frequency must not be below minimum frequency")
        if self.datasheet_url is not None:
            parsed = urlsplit(self.datasheet_url)
            if (
                parsed.scheme != "https"
                or not parsed.hostname
                or parsed.username
                or parsed.password
            ):
                raise ValueError("Device reference URL must be an absolute HTTPS URL")
        return self


class DeviceSearch(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    query: str = Field(default="", max_length=160)
    manufacturer: str | None = Field(default=None, max_length=120)
    technology: str | None = Field(default=None, max_length=120)
    frequency_mhz: float | None = Field(default=None, gt=0, strict=True, allow_inf_nan=False)
    max_results: int = Field(default=100, ge=1, le=MAX_SEARCH_RESULTS, strict=True)


class SearchResults(BaseModel):
    items: tuple[CatalogDevice, ...]
    total_matches: int = Field(ge=0)
    truncated: bool


def device_reference(item: CatalogDevice) -> DeviceReference:
    """Return an immutable, explicitly attached provenance record."""
    return DeviceReference(
        device_id=item.record.device_id,
        part_number=item.record.part_number,
        manufacturer=item.record.manufacturer,
        technology=item.record.technology,
        freq_min_mhz=item.record.freq_min_mhz,
        freq_max_mhz=item.record.freq_max_mhz,
        knowledge_source=item.record.knowledge_source,
        knowledge_confidence=item.record.knowledge_confidence,
        status=item.record.status,
        datasheet_url=item.record.datasheet_url,
        catalog_source_file=item.source_file,
        catalog_source_sha256=item.source_sha256,
    )


def _reject_constant(value: str) -> None:
    raise ValueError(f"Non-finite JSON constant is not permitted: {value}")


def _finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"Non-finite JSON number is not permitted: {value}")
    return parsed


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON object key: {key}")
        result[key] = value
    return result


def load_device_catalog(root: Path) -> tuple[CatalogDevice, ...]:
    """Read only immediate vendor devices.json files; perform no network or writes."""
    if not root.is_dir() or root.is_symlink():
        raise ValueError("Device KB root must be an existing, non-symlink directory")

    devices: list[CatalogDevice] = []
    seen_ids: set[str] = set()
    total_bytes = 0
    for vendor_dir in sorted(root.iterdir(), key=lambda path: path.name.casefold()):
        if vendor_dir.name.startswith("_") or not vendor_dir.is_dir():
            continue
        if vendor_dir.is_symlink():
            raise ValueError(f"KB vendor directory must not be a symlink: {vendor_dir.name}")
        source = vendor_dir / "devices.json"
        if not source.exists():
            continue
        if source.is_symlink() or not source.is_file():
            raise ValueError(f"KB source must be a regular, non-symlink file: {source.name}")
        size = source.stat().st_size
        if size > MAX_KB_FILE_BYTES:
            raise ValueError(f"KB source exceeds the 8 MiB limit: {source.name}")
        total_bytes += size
        if total_bytes > MAX_KB_TOTAL_BYTES:
            raise ValueError("Combined KB sources exceed the 32 MiB limit")

        content = source.read_bytes()
        try:
            parsed = json.loads(
                content.decode("utf-8-sig"),
                parse_constant=_reject_constant,
                parse_float=_finite_float,
                object_pairs_hook=_unique_object,
            )
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ValueError(f"Invalid UTF-8 JSON in KB source {source.name}: {exc}") from exc
        except ValueError as exc:
            raise ValueError(f"Invalid KB JSON in source {source.name}: {exc}") from exc
        if not isinstance(parsed, list):
            raise ValueError(f"KB source must contain a JSON array: {source.name}")
        digest = hashlib.sha256(content).hexdigest()
        relative_source = f"{vendor_dir.name}/devices.json"
        for index, raw_record in enumerate(parsed):
            if not isinstance(raw_record, dict):
                raise ValueError(f"KB record {index} in {relative_source} must be an object")
            payload = dict(raw_record)
            payload.pop("_comment", None)
            try:
                record = DeviceRecord.model_validate(payload)
            except (ValueError, TypeError) as exc:
                raise ValueError(f"Invalid KB record {index} in {relative_source}: {exc}") from exc
            if record.device_id in seen_ids:
                raise ValueError(f"Duplicate KB device_id across vendor files: {record.device_id}")
            seen_ids.add(record.device_id)
            devices.append(
                CatalogDevice(
                    record=record,
                    source_file=relative_source,
                    source_sha256=digest,
                )
            )
            if len(devices) > MAX_KB_DEVICES:
                raise ValueError("Device KB exceeds the 10,000-record limit")
    if not devices:
        raise ValueError(f"No vendor devices.json records found in KB root: {root}")
    return tuple(devices)


def search_devices(catalog: tuple[CatalogDevice, ...], criteria: DeviceSearch) -> SearchResults:
    """Apply deterministic case-insensitive AND filters to the validated local records."""
    validated = DeviceSearch.model_validate_json(criteria.model_dump_json())
    query = validated.query.strip().casefold()
    frequency = validated.frequency_mhz
    if frequency is not None and (isinstance(frequency, bool) or not math.isfinite(frequency)):
        raise ValueError("Search frequency must be finite")

    matches: list[CatalogDevice] = []
    for item in catalog:
        record = item.record
        if validated.manufacturer and (
            record.manufacturer.casefold() != validated.manufacturer.strip().casefold()
        ):
            continue
        if validated.technology and (
            record.technology.casefold() != validated.technology.strip().casefold()
        ):
            continue
        if frequency is not None and not (record.freq_min_mhz <= frequency <= record.freq_max_mhz):
            continue
        if query:
            searchable = json.dumps(
                record.model_dump(mode="json", exclude_none=True),
                ensure_ascii=False,
                sort_keys=True,
                allow_nan=False,
            ).casefold()
            if query not in searchable:
                continue
        matches.append(item)

    matches.sort(
        key=lambda item: (
            item.record.manufacturer.casefold(),
            item.record.part_number.casefold(),
            item.record.device_id,
        )
    )
    return SearchResults(
        items=tuple(matches[: validated.max_results]),
        total_matches=len(matches),
        truncated=len(matches) > validated.max_results,
    )
