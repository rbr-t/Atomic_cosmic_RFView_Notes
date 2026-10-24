"""Local single-user transactional project snapshots; not an authentication boundary."""

import hashlib
import json
import os
import sqlite3
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field, field_validator

from rfview.domain.models import CanvasWorkspace, OperatingPoint
from rfview.services import MAX_DOCUMENT_BYTES

MAX_REVISION = 2**63 - 1


class ProjectSnapshot(BaseModel):
    model_config = ConfigDict(extra="forbid")

    format: Literal["rfview-project-v1"] = "rfview-project-v1"
    workspace: CanvasWorkspace
    operating_point: OperatingPoint


class ProjectInfo(BaseModel):
    id: str
    name: str
    revision: int = Field(ge=1, le=MAX_REVISION)
    updated_at: str

    @field_validator("name")
    @classmethod
    def valid_name(cls, value: str) -> str:
        if not value.strip() or len(value) > 120 or not value.isprintable():
            raise ValueError("Project name requires 1-120 characters without control characters")
        return value.strip()


class SavedProject(BaseModel):
    info: ProjectInfo
    snapshot_revision: int
    created_at: str
    snapshot: ProjectSnapshot


class ProjectConflict(ValueError):
    """A different browser/session saved a newer project revision."""


def default_project_path() -> Path:
    override = os.environ.get("RFVIEW_PROJECT_DB")
    if override is not None:
        if not override.strip():
            raise ValueError("RFVIEW_PROJECT_DB must be a nonempty absolute SQLite path")
        path = Path(override)
        if not path.is_absolute():
            raise ValueError("RFVIEW_PROJECT_DB must be an absolute path")
        return path
    base = Path(os.environ.get("LOCALAPPDATA") or Path.home() / ".local" / "share")
    return base / "RFView" / "projects.sqlite3"


def _project_id(value: str) -> str:
    try:
        canonical = str(UUID(value))
    except (ValueError, AttributeError) as exc:
        raise ValueError("Project identifier must be a canonical UUID") from exc
    if canonical != value:
        raise ValueError("Project identifier must be a canonical UUID")
    return value


def _revision(value: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= MAX_REVISION:
        raise ValueError("Project revision must be a positive integer within SQLite's 64-bit range")
    return value


def _payload(snapshot: ProjectSnapshot) -> tuple[str, str]:
    validated = ProjectSnapshot.model_validate_json(snapshot.model_dump_json())
    text = json.dumps(
        validated.model_dump(mode="json", by_alias=True),
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )
    encoded = text.encode("utf-8")
    if len(encoded) > MAX_DOCUMENT_BYTES:
        raise ValueError("Project snapshot exceeds the 5 MiB limit")
    return text, hashlib.sha256(encoded).hexdigest()


class ProjectStore:
    def __init__(self, path: Path) -> None:
        self.path = path

    @contextmanager
    def _connection(self) -> Iterator[sqlite3.Connection]:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(self.path, timeout=10, isolation_level=None)
        connection.row_factory = sqlite3.Row
        try:
            connection.execute("PRAGMA foreign_keys = ON")
            connection.execute("BEGIN IMMEDIATE")
            version = connection.execute("PRAGMA user_version").fetchone()[0]
            if version not in (0, 1):
                raise ValueError("Unsupported project database schema; no data modified")
            if version == 0:
                existing = connection.execute(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
                ).fetchall()
                if existing:
                    raise ValueError("Database is not an empty RFView project database")
                connection.execute(
                    "CREATE TABLE projects (id TEXT PRIMARY KEY, name TEXT NOT NULL, "
                    "revision INTEGER NOT NULL CHECK(revision>0), updated_at TEXT NOT NULL)"
                )
                connection.execute(
                    "CREATE TABLE snapshots (project_id TEXT NOT NULL REFERENCES projects(id), "
                    "revision INTEGER NOT NULL CHECK(revision>0), created_at TEXT NOT NULL, "
                    "payload TEXT NOT NULL, sha256 TEXT NOT NULL, "
                    "PRIMARY KEY(project_id, revision))"
                )
                connection.execute("PRAGMA user_version = 1")
            yield connection
            connection.commit()
        except (sqlite3.Error, ValueError, TypeError):
            connection.rollback()
            raise
        finally:
            connection.close()

    def list_projects(self, *, page: int = 1) -> tuple[ProjectInfo, ...]:
        if (
            isinstance(page, bool)
            or not isinstance(page, int)
            or not 1 <= page <= MAX_REVISION // 100
        ):
            raise ValueError(
                "Project catalogue page must be a positive integer within SQLite's range"
            )
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT id,name,revision,updated_at FROM projects "
                "ORDER BY updated_at DESC,id LIMIT 100 OFFSET ?",
                ((page - 1) * 100,),
            ).fetchall()
            return tuple(ProjectInfo.model_validate(dict(row)) for row in rows)

    def create(self, name: str, snapshot: ProjectSnapshot) -> SavedProject:
        now = datetime.now(UTC).isoformat()
        info = ProjectInfo(id=str(uuid4()), name=name, revision=1, updated_at=now)
        payload, digest = _payload(snapshot)
        with self._connection() as connection:
            connection.execute(
                "INSERT INTO projects VALUES (?,?,?,?)", (info.id, info.name, 1, now)
            )
            connection.execute(
                "INSERT INTO snapshots VALUES (?,?,?,?,?)", (info.id, 1, now, payload, digest)
            )
        return SavedProject(
            info=info,
            snapshot_revision=1,
            created_at=now,
            snapshot=ProjectSnapshot.model_validate_json(payload),
        )

    def save(
        self, project_id: str, expected_revision: int, snapshot: ProjectSnapshot
    ) -> SavedProject:
        _project_id(project_id)
        _revision(expected_revision)
        _revision(expected_revision + 1)
        payload, digest = _payload(snapshot)
        now = datetime.now(UTC).isoformat()
        with self._connection() as connection:
            row = connection.execute("SELECT * FROM projects WHERE id=?", (project_id,)).fetchone()
            if row is None:
                raise ValueError("Project does not exist")
            if row["revision"] != expected_revision:
                raise ProjectConflict("Project changed in another session; reload or create a copy")
            revision = expected_revision + 1
            connection.execute(
                "INSERT INTO snapshots VALUES (?,?,?,?,?)",
                (project_id, revision, now, payload, digest),
            )
            connection.execute(
                "UPDATE projects SET revision=?,updated_at=? WHERE id=?",
                (revision, now, project_id),
            )
            info = ProjectInfo(id=project_id, name=row["name"], revision=revision, updated_at=now)
        return SavedProject(
            info=info,
            snapshot_revision=revision,
            created_at=now,
            snapshot=ProjectSnapshot.model_validate_json(payload),
        )

    def load(self, project_id: str, revision: int | None = None) -> SavedProject:
        _project_id(project_id)
        if revision is not None:
            _revision(revision)
        with self._connection() as connection:
            project = connection.execute(
                "SELECT * FROM projects WHERE id=?", (project_id,)
            ).fetchone()
            if project is None:
                raise ValueError("Project does not exist")
            info = ProjectInfo.model_validate(dict(project))
            requested = info.revision if revision is None else revision
            row = connection.execute(
                "SELECT created_at,payload,sha256 FROM snapshots WHERE project_id=? AND revision=?",
                (project_id, requested),
            ).fetchone()
            if row is None:
                raise ValueError("Requested project snapshot does not exist")
            text = row["payload"]
            if not isinstance(text, str) or len(text.encode("utf-8")) > MAX_DOCUMENT_BYTES:
                raise ValueError("Stored project snapshot exceeds the 5 MiB limit or is invalid")
            if hashlib.sha256(text.encode("utf-8")).hexdigest() != row["sha256"]:
                raise ValueError("Stored project snapshot checksum mismatch; snapshot not loaded")
            snapshot = ProjectSnapshot.model_validate_json(text)
            return SavedProject(
                info=info,
                snapshot_revision=requested,
                created_at=row["created_at"],
                snapshot=snapshot,
            )
