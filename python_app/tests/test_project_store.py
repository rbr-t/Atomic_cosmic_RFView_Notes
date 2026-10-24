import json
import sqlite3
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest
from pydantic import ValidationError

from rfview.domain.models import CanvasWorkspace, LineupDocument, OperatingPoint
from rfview.project_store import (
    ProjectConflict,
    ProjectSnapshot,
    ProjectStore,
    default_project_path,
)
from rfview.services import MAX_DOCUMENT_BYTES, example_document


def snapshot(power: float = 21) -> ProjectSnapshot:
    documents = {str(index): example_document() for index in range(1, 5)}
    for key, document in documents.items():
        document.metadata["slot"] = key
        document.metadata["extra"] = {"unicode": "\u03a9", "nested": [None, True, 12]}
        document.components[0].model_extra["rotation"] = 90
    return ProjectSnapshot(
        workspace=CanvasWorkspace(format="rfview-workspace-v1", active="3", canvases=documents),
        operating_point=OperatingPoint(
            input_power_dbm=power,
            backoff_db=8,
            architecture="conventional",
            use_canvas_operating_points=True,
        ),
    )


def test_round_trip_across_connections_preserves_every_slot_and_operating_point(
    tmp_path: Path,
) -> None:
    path = tmp_path / "nested" / "projects.sqlite3"
    assert not path.exists()
    original = snapshot()
    saved = ProjectStore(path).create("  PA study  ", original)
    assert saved.info.name == "PA study"
    assert saved.info.revision == saved.snapshot_revision == 1
    loaded = ProjectStore(path).load(saved.info.id)
    assert loaded.snapshot == original
    assert loaded == saved
    assert ProjectStore(path).list_projects() == (saved.info,)
    original.workspace.canvases["1"].metadata["slot"] = "changed"
    assert ProjectStore(path).load(saved.info.id).snapshot != original


def test_immutable_history_and_recovery_creates_new_head(tmp_path: Path) -> None:
    store = ProjectStore(tmp_path / "project.db")
    first = store.create("study", snapshot(21))
    second = store.save(first.info.id, 1, snapshot(22))
    recovered = store.load(first.info.id, 1)
    assert recovered.info.revision == 2
    assert recovered.snapshot_revision == 1
    assert recovered.snapshot.operating_point.input_power_dbm == 21
    third = store.save(first.info.id, recovered.info.revision, recovered.snapshot)
    assert third.snapshot_revision == third.info.revision == 3
    unchanged = store.load(first.info.id, 2)
    assert unchanged.snapshot == second.snapshot
    assert unchanged.created_at == second.created_at
    assert unchanged.snapshot_revision == 2
    assert unchanged.info.revision == 3
    assert store.load(first.info.id, 1).snapshot == first.snapshot
    assert third.snapshot == first.snapshot


def test_stale_session_save_never_overwrites(tmp_path: Path) -> None:
    store = ProjectStore(tmp_path / "project.db")
    first = store.create("study", snapshot())
    head = store.save(first.info.id, 1, snapshot(22))
    with pytest.raises(ProjectConflict, match="another session"):
        ProjectStore(store.path).save(first.info.id, 1, snapshot(23))
    assert store.load(first.info.id) == head
    with pytest.raises(ValueError, match="does not exist"):
        store.load(first.info.id, 3)


def test_concurrent_writers_only_one_can_advance_revision(tmp_path: Path) -> None:
    store = ProjectStore(tmp_path / "project.db")
    project = store.create("study", snapshot())

    def save(power: float) -> bool:
        try:
            ProjectStore(store.path).save(project.info.id, 1, snapshot(power))
            return True
        except ProjectConflict:
            return False

    with ThreadPoolExecutor(max_workers=2) as executor:
        outcomes = list(executor.map(save, [22.0, 23.0]))
    assert sorted(outcomes) == [False, True]
    assert store.load(project.info.id).info.revision == 2


def test_failed_transaction_rolls_back_snapshot_insert(tmp_path: Path) -> None:
    store = ProjectStore(tmp_path / "project.db")
    project = store.create("study", snapshot())
    with sqlite3.connect(store.path) as connection:
        connection.execute(
            "CREATE TRIGGER reject_update BEFORE UPDATE ON projects "
            "BEGIN SELECT RAISE(ABORT, 'test failure'); END"
        )
    with pytest.raises(sqlite3.IntegrityError, match="test failure"):
        store.save(project.info.id, 1, snapshot(22))
    assert store.load(project.info.id) == project
    with pytest.raises(ValueError, match="does not exist"):
        store.load(project.info.id, 2)


@pytest.mark.parametrize("payload", ['{"broken":true}', "invalid", "x" * (MAX_DOCUMENT_BYTES + 1)],
ids=["changed-json", "invalid-json", "oversized"],)
def test_corruption_is_explicit_and_older_snapshot_survives(tmp_path: Path, payload: str) -> None:
    store = ProjectStore(tmp_path / "project.db")
    first = store.create("study", snapshot())
    store.save(first.info.id, 1, snapshot(22))
    with sqlite3.connect(store.path) as connection:
        connection.execute(
            "UPDATE snapshots SET payload=? WHERE project_id=? AND revision=2",
            (payload, first.info.id),
        )
    with pytest.raises(ValueError, match="checksum|limit"):
        store.load(first.info.id)
    assert store.load(first.info.id, 1).snapshot == first.snapshot
    with sqlite3.connect(store.path) as connection:
        assert connection.execute("SELECT COUNT(*) FROM snapshots").fetchone()[0] == 2


def test_payload_schema_is_validated_even_with_matching_checksum(tmp_path: Path) -> None:
    import hashlib

    store = ProjectStore(tmp_path / "project.db")
    first = store.create("study", snapshot())
    payload = json.dumps({"format": "future", "workspace": {}})
    with sqlite3.connect(store.path) as connection:
        connection.execute(
            "UPDATE snapshots SET payload=?,sha256=?",
            (payload, hashlib.sha256(payload.encode()).hexdigest()),
        )
    with pytest.raises(ValidationError):
        store.load(first.info.id)


@pytest.mark.parametrize("name", ["", " ", "x" * 121, "bad\nname", "bad\x00name", "bad\x7fname"])
def test_invalid_names_do_not_create_database(tmp_path: Path, name: str) -> None:
    store = ProjectStore(tmp_path / "project.db")
    with pytest.raises(ValueError, match="Project name"):
        store.create(name, snapshot())
    assert not store.path.exists()


def test_project_names_are_data_not_sql_and_may_repeat(tmp_path: Path) -> None:
    store = ProjectStore(tmp_path / "project.db")
    name = "'); DROP TABLE projects;--"
    first = store.create(name, snapshot())
    second = store.create(name, snapshot())
    assert first.info.id != second.info.id
    assert len(store.list_projects()) == 2
    assert store.load(first.info.id).info.name == name


def test_catalogue_pages_keep_older_projects_accessible(tmp_path: Path) -> None:
    store = ProjectStore(tmp_path / "project.db")
    value = snapshot()
    first = store.create("earliest", value)
    for index in range(100):
        store.create(f"project {index}", value)
    assert len(store.list_projects()) == 100
    assert store.list_projects(page=2) == (first.info,)
    assert store.list_projects(page=3) == ()


@pytest.mark.parametrize("page", [0, -1, True, 1.5, 2**63])
def test_invalid_catalogue_pages_do_not_create_database(tmp_path: Path, page: int) -> None:
    store = ProjectStore(tmp_path / "project.db")
    with pytest.raises(ValueError, match="catalogue page"):
        store.list_projects(page=page)
    assert not store.path.exists()


@pytest.mark.parametrize("revision", [0, -1, True, 1.5, 2**63])
def test_invalid_revisions_rejected(tmp_path: Path, revision: int) -> None:
    store = ProjectStore(tmp_path / "project.db")
    first = store.create("study", snapshot())
    with pytest.raises(ValueError, match="positive integer"):
        store.save(first.info.id, revision, snapshot())
    with pytest.raises(ValueError, match="positive integer"):
        store.load(first.info.id, revision)
    assert store.load(first.info.id).info.revision == 1


@pytest.mark.parametrize("identifier", ["../other.db", "", "not-a-uuid"])
def test_invalid_project_identifiers_never_become_paths(tmp_path: Path, identifier: str) -> None:
    store = ProjectStore(tmp_path / "project.db")
    with pytest.raises(ValueError, match="UUID"):
        store.load(identifier)
    assert not store.path.exists()


def test_snapshot_size_limit_before_any_write(tmp_path: Path) -> None:
    store = ProjectStore(tmp_path / "project.db")
    value = snapshot()
    value.workspace.canvases["1"].metadata["oversized"] = "x" * MAX_DOCUMENT_BYTES
    with pytest.raises(ValueError, match="5 MiB"):
        store.create("study", value)
    assert not store.path.exists()


def test_mutated_invalid_snapshot_is_revalidated_before_save(tmp_path: Path) -> None:
    store = ProjectStore(tmp_path / "project.db")
    value = snapshot()
    value.workspace.canvases.pop("4")
    with pytest.raises(ValidationError):
        store.create("study", value)
    assert not store.path.exists()


def test_old_workspace_contract_unchanged() -> None:
    old = snapshot().workspace
    loaded = CanvasWorkspace.model_validate_json(old.model_dump_json())
    assert loaded == old
    with pytest.raises(ValidationError):
        ProjectSnapshot.model_validate_json(old.model_dump_json())
    assert LineupDocument.model_validate_json(old.canvases["1"].model_dump_json())


@pytest.mark.parametrize("version", [2, 100])
def test_future_database_versions_are_not_modified(tmp_path: Path, version: int) -> None:
    path = tmp_path / "project.db"
    with sqlite3.connect(path) as connection:
        connection.execute(f"PRAGMA user_version = {version}")
    with pytest.raises(ValueError, match="Unsupported"):
        ProjectStore(path).list_projects()
    with sqlite3.connect(path) as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == version
        assert not connection.execute("SELECT name FROM sqlite_master").fetchall()


def test_non_rfview_database_is_never_adopted(tmp_path: Path) -> None:
    path = tmp_path / "other.db"
    with sqlite3.connect(path) as connection:
        connection.execute("CREATE TABLE other (value TEXT)")
        connection.execute("INSERT INTO other VALUES ('preserve')")
    with pytest.raises(ValueError, match="not an empty RFView"):
        ProjectStore(path).list_projects()
    with sqlite3.connect(path) as connection:
        assert connection.execute("SELECT value FROM other").fetchone()[0] == "preserve"
        assert connection.execute("PRAGMA user_version").fetchone()[0] == 0


def test_unwritable_target_is_not_a_successful_save(tmp_path: Path) -> None:
    with pytest.raises(sqlite3.OperationalError):
        ProjectStore(tmp_path).create("study", snapshot())


def test_default_path_and_explicit_override(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.delenv("RFVIEW_PROJECT_DB", raising=False)
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path))
    assert default_project_path() == tmp_path / "RFView" / "projects.sqlite3"
    target = tmp_path / "custom.db"
    monkeypatch.setenv("RFVIEW_PROJECT_DB", str(target))
    assert default_project_path() == target
    for invalid in ("", "relative.db"):
        monkeypatch.setenv("RFVIEW_PROJECT_DB", invalid)
        with pytest.raises(ValueError, match="absolute"):
            default_project_path()
    assert not target.exists()
