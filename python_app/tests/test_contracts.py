import ast
import json
import math
from pathlib import Path

import pytest
from pydantic import ValidationError

from rfview.domain.lineup import calculate_lineup
from rfview.domain.models import LineupDocument, OperatingPoint
from rfview.domain.planning import link_budget, passive_loss
from rfview.domain.power import dbm_to_watts, sum_dbm
from rfview.domain.rf_tools import sparams, thermal
from rfview.domain.transistor import gate_width, matching_lmatch, ropt
from rfview.services import (
    MAX_DOCUMENT_BYTES,
    example_document,
    operating_point,
    parse_document,
    serialize_document,
    with_operating_point,
)


def test_round_trip_retains_ids_connections_extras_and_transforms() -> None:
    data = example_document().model_dump(mode="json", by_alias=True)
    data["custom_field"] = {"future": ["preserve", None, 4]}
    data["components"][0].update(rotation=90, flipH=True, textOffset={"x": 3, "y": 4})
    data["connections"][0]["fromPort"] = "output"
    data["metadata"]["provenance"] = {"vendor": "reference"}
    document = LineupDocument.model_validate(data)
    assert json.loads(serialize_document(document)) == data


@pytest.mark.parametrize(
    "edges",
    [
        [{"from": 10, "to": 999}],
        [{"from": 10, "to": 10}],
        [{"from": 10, "to": 20}, {"from": 20, "to": 10}],
        [{"from": 10, "to": 20}, {"from": 10, "to": 20}],
    ],
)
def test_invalid_graph_is_rejected(edges: list[dict[str, int]]) -> None:
    data = example_document().model_dump(by_alias=True)
    data["connections"] = edges
    with pytest.raises(ValidationError):
        LineupDocument.model_validate(data)


def test_duplicate_ids_are_rejected() -> None:
    data = example_document().model_dump(by_alias=True)
    data["components"][1]["id"] = "10"
    with pytest.raises(ValidationError, match="unique"):
        LineupDocument.model_validate(data)


@pytest.mark.parametrize("identifier", [2**53, -(2**53)])
def test_unsafe_browser_numeric_ids_are_rejected(identifier: int) -> None:
    with pytest.raises(ValidationError, match="JavaScript"):
        parse_document(json.dumps({"components": [{"id": identifier, "type": "transistor"}]}))


def test_operating_point_round_trip_does_not_mutate_document() -> None:
    document = example_document()
    original = serialize_document(document)
    point = OperatingPoint(
        input_power_dbm=21,
        backoff_db=8,
        architecture="conventional",
        use_canvas_operating_points=True,
    )
    saved = parse_document(serialize_document(with_operating_point(document, point)))
    assert operating_point(saved) == point
    assert serialize_document(document) == original
    assert operating_point(document) is None


@pytest.mark.parametrize(
    "settings",
    [
        {"input_power_dbm": 101},
        {"input_power_dbm": float("nan")},
        {"backoff_db": -1},
        {"architecture": "unknown"},
        {"unrecognized": True},
    ],
)
def test_invalid_saved_operating_point_is_rejected(settings: dict[str, object]) -> None:
    document = example_document()
    document.metadata["python_operating_point"] = settings
    with pytest.raises(ValidationError):
        operating_point(document)


@pytest.mark.parametrize("value", ["NaN", "Infinity", "-Infinity"])
def test_nonfinite_input_rejected(value: str) -> None:
    with pytest.raises(ValueError):
        parse_document(
            f'{{"components":[{{"id":1,"type":"transistor","properties":{{"gain":{value}}}}}]}}'
        )


def test_oversized_input_rejected() -> None:
    with pytest.raises(ValueError, match="5 MiB"):
        parse_document(" " * (MAX_DOCUMENT_BYTES + 1))


def test_future_version_and_unknown_components_rejected() -> None:
    with pytest.raises(ValidationError):
        parse_document('{"schema_version":"2.0","components":[]}')
    with pytest.raises(ValidationError):
        parse_document('{"components":[{"id":1,"type":"not-a-device"}]}')


def test_state_and_calculations_do_not_mutate_inputs() -> None:
    first, second = example_document(), example_document()
    original = serialize_document(first)
    calculate_lineup(first)
    assert serialize_document(first) == original
    first.components[0].properties["loss"] = 99
    assert second.components[0].properties["loss"] == 0.3


def test_branched_power_is_conserved_through_split_and_combine() -> None:
    document = example_document()
    result = calculate_lineup(document, 20, 6, "doherty")
    assert result.final_pout_dbm == pytest.approx(35.4)
    assert result.net_gain_db == pytest.approx(15.4)
    assert result.system_de >= result.system_pae
    assert result.stage_results[0].pout_dbm == pytest.approx(20 - 10 * math.log10(2) - 0.3)
    assert result.final_pout_bo_dbm < result.final_pout_dbm


def test_saved_operating_points_can_be_explicitly_ignored() -> None:
    document = parse_document(
        json.dumps(
            {
                "components": [
                    {
                        "id": 1,
                        "type": "transistor",
                        "properties": {
                            "gain": 15,
                            "p1db": 50,
                            "pout_p3db": 40,
                            "pout_pavg": 35,
                            "pin_p3db": 20,
                            "pin_pavg": 14,
                        },
                    }
                ]
            }
        )
    )
    legacy = calculate_lineup(document, 10)
    recomputed = calculate_lineup(document, 10, use_canvas_operating_points=False)
    assert legacy.final_pout_dbm == 40
    assert recomputed.final_pout_dbm == 23


@pytest.mark.parametrize(
    "field,value",
    [
        ("pae", 0),
        ("pae", 101),
        ("vdd", 0),
        ("rth", -1),
        ("gain", True),
        ("gain", "NaN"),
    ],
)
def test_invalid_device_properties_fail_explicitly(field: str, value: object) -> None:
    data = example_document().model_dump(by_alias=True)
    data["components"][1]["properties"][field] = value
    with pytest.raises(ValueError):
        calculate_lineup(LineupDocument.model_validate(data))


def test_unsupported_branching_and_unequal_split_fail() -> None:
    document = example_document()
    document.components[0].properties["split_ratio"] = 2
    with pytest.raises(ValueError, match="split_ratio"):
        calculate_lineup(document)
    document = example_document()
    document.components[0].type = "matching"
    with pytest.raises(ValueError, match="splitter"):
        calculate_lineup(document)


def test_empty_document_can_be_saved_but_not_calculated() -> None:
    empty = parse_document('{"components":[]}')
    assert json.loads(serialize_document(empty))["components"] == []
    with pytest.raises(ValueError, match="No components"):
        calculate_lineup(empty)


def test_numerical_validation_and_reference_points() -> None:
    assert sum_dbm([47, 47]) == pytest.approx(50.0102999566)
    assert ropt(28, 10, 2) == 33.8
    assert gate_width(10, 2.5, 0.5) == 4
    assert sparams(0, 0)["return_loss_db"] is None
    assert sparams(1, 0)["vswr"] is None
    assert matching_lmatch(50, 50, 3.5)["topology"] == "none"
    with pytest.raises(ValueError):
        dbm_to_watts(float("nan"))
    with pytest.raises(ValueError):
        passive_loss("not-a-device", 3.5)
    with pytest.raises(ValueError):
        thermal(10, 0)
    with pytest.raises(ValueError):
        ropt(1, 10, 2)
    with pytest.raises(ValueError):
        link_budget(30, 0, 0, 0, 3.5, 10, 5, 10)


def test_domain_has_no_ui_storage_or_network_imports() -> None:
    root = Path(__file__).resolve().parents[1] / "src" / "rfview" / "domain"
    allowed = {
        "__future__",
        "collections",
        "csv",
        "dataclasses",
        "json",
        "math",
        "re",
        "typing",
        "pydantic",
        "rfview",
        "scipy",
    }
    for path in root.glob("*.py"):
        for node in ast.walk(ast.parse(path.read_text())):
            if isinstance(node, ast.Import):
                assert all(alias.name.split(".")[0] in allowed for alias in node.names)
            elif isinstance(node, ast.ImportFrom):
                assert (node.module or "").split(".")[0] in allowed
