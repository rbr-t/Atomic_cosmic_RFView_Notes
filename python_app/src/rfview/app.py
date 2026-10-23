from __future__ import annotations

import json
import logging
from collections.abc import Iterator
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field, JsonValue, ValidationError
from shiny import App, Inputs, Outputs, Session, reactive, render, ui

from rfview.domain.guardrails import DeviceParameters, validate_device_params
from rfview.domain.lineup import calculate_lineup
from rfview.domain.models import LineupDocument, LineupResult, OperatingPoint
from rfview.domain.touchstone import TouchstoneData
from rfview.domain.transistor import (
    DesignTopology,
    StageSizingInput,
    gate_width,
    ropt,
    transistor_design_suite,
)
from rfview.services import (
    example_document,
    operating_point,
    read_document,
    read_guardrails,
    read_touchstone,
    serialize_document,
    with_operating_point,
)
from rfview.technology_ui import technology_panel
from rfview.touchstone_ui import MAX_VIEWER_FREQUENCIES, touchstone_panel

logger = logging.getLogger(__name__)
PACKAGE_ROOT = Path(__file__).resolve().parent
PYTHON_ROOT = PACKAGE_ROOT.parents[1]
REPOSITORY_ROOT = PYTHON_ROOT.parent
CANVAS_ROOT = REPOSITORY_ROOT / "PA design App" / "assets" / "js" / "common"
D3_ROOT = PYTHON_ROOT / "node_modules" / "d3" / "dist"
GUARDRAILS = read_guardrails(
    REPOSITORY_ROOT / "PA design App" / "config" / "technology_guardrails.yaml"
)


class BrowserAction(BaseModel):
    action: str
    document: LineupDocument
    request_id: int


class SizingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    stage: StageSizingInput
    freq_ghz: float = Field(gt=0)
    topology: DesignTopology
    er: float = Field(ge=1)
    h_mm: float = Field(gt=0)


def toolbar_button(identifier: str, label: str) -> ui.Tag:
    return ui.tags.button(label, id=identifier, type="button", class_="btn btn-default")


app_ui = ui.page_fluid(
    ui.tags.head(
        ui.tags.link(rel="stylesheet", href="migration/migration.css"),
        ui.tags.script(src="vendor/d3.min.js"),
        ui.tags.script(src="migration/canvas_adapter.js"),
    ),
    ui.tags.header(
        ui.h1("RF PA Design - Python"),
        ui.p(
            "Migration preview - session-only. Legacy R application remains unchanged. "
            "Projects/DB, load-pull, advanced SP features, AI/KB, CAD and document builds "
            "are not ported yet.",
            class_="migration-notice",
        ),
    ),
    ui.layout_sidebar(
        ui.sidebar(
            ui.h2("Operating point"),
            ui.input_numeric("input_power_dbm", "Input power (dBm)", 20, min=-100, max=100),
            ui.input_numeric("backoff_db", "Backoff (dB)", 6, min=0, max=60),
            ui.input_select(
                "architecture",
                "Architecture",
                {"conventional": "Conventional", "doherty": "Doherty"},
                selected="doherty",
            ),
            ui.input_checkbox(
                "use_canvas_operating_points", "Use saved browser operating points", False
            ),
            ui.p(
                "Off: recalculate from gain and system inputs. "
                "On: reproduce legacy saved dual operating points when present."
            ),
            ui.input_action_button("example", "Load branched example"),
            ui.input_file("load_document", "Load lineup JSON (max 5 MiB)", accept=[".json"]),
            ui.output_ui("download_control"),
            ui.h2("Selected transistor"),
            ui.output_ui("selected_properties"),
            ui.tags.details(
                ui.tags.summary("Technology guardrail advisory"),
                ui.p(
                    "Checks applied component properties, not uncommitted edits. "
                    "Technology/frequency below are advisory only and are not saved "
                    "or used by the lineup calculation."
                ),
                ui.input_select(
                    "guardrail_technology",
                    "Technology for advisory",
                    {
                        "": "Choose technology",
                        **{key: tech.label for key, tech in GUARDRAILS.technologies.items()},
                    },
                ),
                ui.input_numeric("guardrail_frequency", "Advisory frequency (GHz)", 3.5, min=0),
                ui.input_checkbox("guardrail_check_density", "Check power density", False),
                ui.input_numeric("guardrail_density", "Advisory power density (W/mm)", 5, min=0),
                ui.output_code("guardrail_advisory"),
                ui.p(
                    "Legacy rule subset, not a safety certification. No thermal, "
                    "Pout, breakdown derating or compression validation is performed here."
                ),
            ),
            ui.h2("Sizing check"),
            ui.input_numeric("sizing_vdd", "Supply voltage (V)", 28, min=0),
            ui.input_numeric("sizing_vknee", "Knee voltage (V)", 2, min=0),
            ui.input_numeric("sizing_pout", "Output power (W)", 10, min=0),
            ui.input_numeric("sizing_density", "Power density (W/mm)", 2.5, min=0),
            ui.output_code("sizing"),
            width=310,
        ),
        ui.div(
            toolbar_button("python_calculate", "Calculate in Python"),
            toolbar_button("python_add", "Add transistor"),
            toolbar_button("python_wire", "Wire mode"),
            toolbar_button("python_undo", "Undo"),
            toolbar_button("python_redo", "Redo"),
            toolbar_button("python_snapshot", "Prepare JSON download"),
            class_="migration-toolbar",
            role="toolbar",
            **{"aria-label": "Lineup actions"},
        ),
        ui.p(
            "Select a component to edit. Drag to move; scroll to zoom. "
            "Wire mode connects component ports. Prepare a fresh download after editing."
        ),
        ui.div(
            id="pa_lineup_canvas_container",
            role="region",
            **{"aria-label": "Interactive RF lineup canvas"},
        ),
        ui.output_text("status"),
        ui.output_ui("summary"),
        ui.output_ui("stage_table"),
        ui.tags.details(
            ui.tags.summary("Touchstone magnitude and phase viewer"),
            ui.p(
                "Session-only Touchstone 1.x .s1p/.s2p viewer, max 5 MiB and "
                "2,000 frequencies. Uploads are not saved in lineup JSON."
            ),
            ui.input_file("touchstone_upload", "Upload Touchstone", accept=[".s1p", ".s2p"]),
            ui.input_select("touchstone_parameter", "S-parameter", ["S11", "S21", "S12", "S22"]),
            ui.input_select(
                "touchstone_representation",
                "Network representation (same row/column indices)",
                {
                    "S": "S magnitude / phase",
                    "Z": "Z real / imaginary (ohm)",
                    "Y": "Y real / imaginary (siemens)",
                },
            ),
            ui.output_text("touchstone_status"),
            ui.output_ui("touchstone_view"),
        ),
        ui.tags.details(
            ui.tags.summary("Full-stage transistor sizing"),
            ui.p(
                "Independent preliminary GaN synthesis. Inputs are session-only, "
                "not saved with lineup JSON or applied to canvas devices. "
                "Output power is a manual target, not automatically taken from lineup results."
            ),
            ui.input_numeric("suite_pout", "Sizing target output power (dBm)", 40),
            ui.input_numeric("suite_pae", "Sizing entered PAE (%)", 55, min=0, max=100),
            ui.input_numeric("suite_vdd", "Sizing supply voltage (V)", 28, min=0),
            ui.input_numeric("suite_frequency", "Sizing frequency (GHz)", 3.5, min=0),
            ui.input_select(
                "suite_topology",
                "Sizing topology",
                {
                    "single_ended": "Single-ended",
                    "doherty_symmetric": "Symmetric Doherty",
                    "doherty_asymmetric_6dB": "Asymmetric Doherty (6 dB)",
                    "doherty_asymmetric_9dB": "Asymmetric Doherty (9 dB)",
                },
                selected="doherty_symmetric",
            ),
            ui.input_numeric(
                "suite_er", "Substrate relative permittivity (dimensionless)", 3.55, min=1
            ),
            ui.input_numeric("suite_h", "Substrate thickness (mm)", 0.508, min=0),
            ui.output_ui("full_stage_sizing"),
        ),
        ui.tags.details(
            ui.tags.summary("Calculation rationale and limitations"),
            ui.output_code("rationale"),
        ),
        ui.tags.details(
            ui.tags.summary("Technology charts and summary"),
            ui.input_select(
                "chart_technology",
                "Chart technology",
                {
                    "all": "All technologies",
                    **{key: tech.label for key, tech in GUARDRAILS.technologies.items()},
                },
            ),
            ui.input_select(
                "chart_pa_class",
                "PA class for backoff curves",
                ["A", "AB", "B", "Doherty", "F"],
                selected="AB",
            ),
            ui.output_ui("technology_charts"),
        ),
    ),
    title="RF PA Design - Python migration",
)


def server(input: Inputs, output: Outputs, session: Session) -> None:
    document: reactive.Value[LineupDocument] = reactive.Value(example_document())
    result: reactive.Value[LineupResult | None] = reactive.Value(None)
    status_state = reactive.Value(
        "Waiting for canvas readiness. No data is persisted on the server."
    )
    selected: reactive.Value[int | str | None] = reactive.Value(None)
    last_serialized = reactive.Value("")
    result_input = reactive.Value("")
    prepared = reactive.Value(False)
    network: reactive.Value[TouchstoneData | None] = reactive.Value(None)
    network_status = reactive.Value("No Touchstone dataset loaded.")

    @reactive.effect
    @reactive.event(input.touchstone_upload)
    def _touchstone_upload() -> None:
        files = input.touchstone_upload()
        if not files:
            return
        try:
            parsed = read_touchstone(Path(files[0]["datapath"]), filename=files[0]["name"])
            if len(parsed.freq_ghz) > MAX_VIEWER_FREQUENCIES:
                raise ValueError(
                    f"Viewer limit is {MAX_VIEWER_FREQUENCIES} frequency records; "
                    "the parser API supports larger datasets."
                )
        except (ValueError, OSError) as exc:
            message = f"Touchstone upload rejected: {exc}. Last valid dataset retained."
            logger.warning("%s", message)
            network_status.set(message)
            ui.notification_show(message, type="error", duration=None, session=session)
            return
        network.set(parsed)
        choices = ["S11"] if parsed.nports == 1 else ["S11", "S21", "S12", "S22"]
        ui.update_select("touchstone_parameter", choices=choices, selected="S11", session=session)
        network_status.set(f"Loaded {parsed.filename}. Session-only; no dataset saved.")

    @render.text
    def touchstone_status() -> str:
        return network_status()

    @render.ui
    def touchstone_view() -> ui.Tag:
        current = network()
        if current is None:
            return ui.p("Upload a supported Touchstone file to view its magnitude and phase.")
        parameter = input.touchstone_parameter()
        if current.nports == 1 and parameter != "S11":
            return ui.p("Updating parameter selection for the one-port dataset.")
        try:
            return touchstone_panel(current, parameter, input.touchstone_representation())
        except ValueError as exc:
            logger.warning("Touchstone view rejected: %s", exc)
            return ui.p(f"Touchstone view rejected: {exc}", role="alert")

    @render.ui
    def technology_charts() -> ui.Tag:
        try:
            return technology_panel(GUARDRAILS, input.chart_technology(), input.chart_pa_class())
        except ValueError as exc:
            logger.warning("Technology charts rejected: %s", exc)
            return ui.p(f"Technology charts rejected: {exc}", role="alert")

    def failure(message: str) -> None:
        logger.warning("%s", message)
        status_state.set(message)
        ui.notification_show(message, type="error", duration=None, session=session)

    async def load_canvas(new_document: LineupDocument) -> None:
        document.set(new_document)
        result.set(None)
        selected.set(None)
        prepared.set(False)
        await session.send_custom_message(
            "pythonLoadConfiguration", new_document.model_dump(mode="json", by_alias=True)
        )

    @reactive.effect
    @reactive.event(input.python_canvas_ready)
    async def _ready() -> None:
        await load_canvas(document())
        status_state.set("Python canvas ready. Load/edit a lineup and calculate; R is not used.")

    @reactive.effect
    @reactive.event(input.example)
    async def _example() -> None:
        await load_canvas(example_document())
        ui.update_numeric("input_power_dbm", value=20, session=session)
        ui.update_numeric("backoff_db", value=6, session=session)
        ui.update_select("architecture", selected="doherty", session=session)

    @reactive.effect
    @reactive.event(input.load_document)
    async def _load() -> None:
        files = input.load_document()
        if not files:
            return
        try:
            new_document = read_document(Path(files[0]["datapath"]))
            saved_point = operating_point(new_document)
        except (ValueError, OSError) as exc:
            failure(f"Load rejected: {exc}")
            return
        await load_canvas(new_document)
        if saved_point is not None:
            ui.update_numeric("input_power_dbm", value=saved_point.input_power_dbm, session=session)
            ui.update_numeric("backoff_db", value=saved_point.backoff_db, session=session)
            ui.update_select("architecture", selected=saved_point.architecture, session=session)
            ui.update_checkbox(
                "use_canvas_operating_points",
                value=saved_point.use_canvas_operating_points,
                session=session,
            )
        status_state.set(
            "Lineup loaded. IDs, connections and additional JSON fields were retained."
        )

    @reactive.effect
    @reactive.event(input.python_canvas_error)
    def _canvas_error() -> None:
        failure(f"Canvas error: {input.python_canvas_error()}")

    @reactive.effect
    @reactive.event(input.python_snapshot)
    def _snapshot() -> None:
        try:
            snapshot = LineupDocument.model_validate(input.python_snapshot())
        except ValidationError as exc:
            prepared.set(False)
            result.set(None)
            failure(f"Invalid canvas: {exc}")
            return
        serialized = serialize_document(snapshot)
        if serialized != last_serialized():
            document.set(snapshot)
            result.set(None)
            prepared.set(False)
            last_serialized.set(serialized)
            status_state.set("Canvas changed. Recalculate and prepare a fresh JSON download.")

    @reactive.effect
    @reactive.event(input.lineup_selected_component)
    def _selection() -> None:
        value = input.lineup_selected_component()
        if isinstance(value, (int, str)) and not isinstance(value, bool):
            selected.set(value)
        else:
            selected.set(None)

    @reactive.effect
    @reactive.event(input.python_action)
    async def _action() -> None:
        try:
            action = BrowserAction.model_validate(input.python_action())
            document.set(action.document)
            last_serialized.set(serialize_document(action.document))
            if action.action == "snapshot":
                prepared.set(True)
                status_state.set("JSON snapshot prepared. Download it using the sidebar button.")
                return
            if action.action != "calculate":
                raise ValueError(f"Unsupported browser action: {action.action}")
            calculated = calculate_lineup(
                action.document,
                input.input_power_dbm(),
                input.backoff_db(),
                input.architecture(),
                use_canvas_operating_points=input.use_canvas_operating_points(),
            )
        except (ValueError, OverflowError) as exc:
            result.set(None)
            failure(f"Calculation rejected: {exc}")
            return
        result.set(calculated)
        result_input.set(_parameters())
        status_state.set(
            "Calculated in Python using legacy-r-v1. Read the model limitations below."
        )
        await session.send_custom_message(
            "pythonResults",
            {
                "stages": [
                    stage.model_dump(exclude_none=True) for stage in calculated.stage_results
                ],
                "request_id": action.request_id,
            },
        )

    def _parameters() -> str:
        return json.dumps(
            [
                input.input_power_dbm(),
                input.backoff_db(),
                input.architecture(),
                input.use_canvas_operating_points(),
            ]
        )

    def current_result() -> LineupResult | None:
        if _parameters() != result_input():
            return None
        return result()

    @render.text
    def status() -> str:
        return status_state()

    @render.ui
    def summary() -> ui.Tag:
        calculated = current_result()
        if calculated is None:
            return ui.p("No current result. Calculate after editing the lineup or operating point.")
        return ui.div(
            ui.h2("System results"),
            ui.p(
                f"Output: {calculated.final_pout_dbm:.3f} dBm | "
                f"backoff: {calculated.final_pout_bo_dbm:.3f} dBm"
            ),
            ui.p(
                f"Net gain: {calculated.net_gain_db:.3f} dB | "
                f"legacy summed gain: {calculated.total_gain:.3f} dB"
            ),
            ui.p(
                f"PAE: {calculated.system_pae:.3f} % | DE: {calculated.system_de:.3f} % | "
                f"DC power: {calculated.total_pdc:.3f} W"
            ),
            class_="rf-results",
        )

    @render.ui
    def stage_table() -> ui.Tag:
        calculated = current_result()
        rows = [] if calculated is None else calculated.stage_results
        headings = ["Stage", "Type", "Pin (dBm)", "Pout (dBm)", "Pout BO (dBm)", "PDC (W)"]
        return ui.div(
            ui.tags.table(
                ui.tags.caption("Per-stage Python calculation results"),
                ui.tags.thead(ui.tags.tr(*(ui.tags.th(label, scope="col") for label in headings))),
                ui.tags.tbody(
                    *(
                        ui.tags.tr(
                            ui.tags.td(stage.stage),
                            ui.tags.td(stage.type),
                            ui.tags.td(f"{stage.pin_dbm:.3f}"),
                            ui.tags.td(f"{stage.pout_dbm:.3f}"),
                            ui.tags.td(f"{stage.pout_bo_dbm:.3f}"),
                            ui.tags.td("-" if stage.pdc_w is None else f"{stage.pdc_w:.3f}"),
                        )
                        for stage in rows
                    )
                ),
            ),
            class_="table-scroll",
        )

    @render.code
    def rationale() -> str:
        calculated = current_result()
        return "No current calculation." if calculated is None else calculated.rationale

    @render.ui
    def selected_properties() -> ui.Tag:
        component = next(
            (item for item in document().components if str(item.id) == str(selected())), None
        )
        if component is None or component.type != "transistor":
            return ui.p("Select a transistor on the canvas.")
        return ui.div(
            ui.p(f"Component ID: {component.id}"),
            ui.input_numeric("edit_gain", "Small-signal gain (dB)", component.number("gain", 15)),
            ui.input_numeric(
                "edit_gain_p3db",
                "Full-power gain (dB)",
                component.number("gain_p3db", component.number("gain", 15) - 2),
            ),
            ui.input_numeric(
                "edit_gain_bo",
                "Backoff gain (dB)",
                component.number(
                    "gain_bo",
                    (
                        component.number("gain", 15)
                        + component.number("gain_p3db", component.number("gain", 15) - 2)
                    )
                    / 2,
                ),
            ),
            ui.input_numeric("edit_pae", "Entered efficiency (%)", component.number("pae", 50)),
            ui.input_numeric("edit_p1db", "P1dB limit (dBm)", component.number("p1db", 43)),
            ui.input_action_button("apply_properties", "Apply transistor properties"),
        )

    @reactive.effect
    @reactive.event(input.apply_properties)
    async def _apply() -> None:
        identifier = selected()
        if identifier is None:
            failure("Select a transistor before editing.")
            return
        properties: dict[str, JsonValue] = {
            "gain": input.edit_gain(),
            "gain_p3db": input.edit_gain_p3db(),
            "gain_bo": input.edit_gain_bo(),
            "pae": input.edit_pae(),
            "p1db": input.edit_p1db(),
        }
        await session.send_custom_message(
            "pythonEditComponent", {"id": identifier, "properties": properties}
        )

    @render.code
    def guardrail_advisory() -> str:
        component = next(
            (item for item in document().components if str(item.id) == str(selected())), None
        )
        if component is None or component.type != "transistor":
            return "Select a transistor on the canvas."
        if not input.guardrail_technology():
            return "Choose a technology explicitly; no technology is inferred."
        try:
            device = DeviceParameters(
                tech_key=input.guardrail_technology(),
                freq_ghz=input.guardrail_frequency(),
                gain_db=component.number("gain", 15),
                pae_pct=component.number("pae", 50),
                pout_dbm=component.number("p1db", 43),
                vdd=component.number("vdd", 28),
                pout_density=(
                    input.guardrail_density() if input.guardrail_check_density() else None
                ),
            )
            validation = validate_device_params(device, GUARDRAILS)
        except ValueError as exc:
            logger.warning("Guardrail advisory rejected: %s", exc)
            return f"Advisory rejected: {exc}"
        return "\n".join(
            [
                f"Status: {validation.status.upper()} | {validation.model_version}",
                f"Technology: {validation.tech}",
                f"Component ID: {component.id} | Vdd: {device.vdd:.1f} V",
                f"Available gain: {validation.max_gain_available:.1f} dB",
                f"Practical PAE limit: {validation.pae_max_practical:.1f} %",
                *(f"ERROR: {message}" for message in validation.errors),
                *(f"WARNING: {message}" for message in validation.warnings),
            ]
        )

    @render.code
    def sizing() -> str:
        try:
            resistance = ropt(input.sizing_vdd(), input.sizing_pout(), input.sizing_vknee())
            width = gate_width(input.sizing_pout(), input.sizing_density(), 0.5)
        except (ValueError, OverflowError) as exc:
            return f"Sizing rejected: {exc}"
        return f"Ropt: {resistance:.3f} ohm\nGate width: {width:.3f} mm"

    @render.ui
    def full_stage_sizing() -> ui.Tag:
        try:
            request = SizingRequest(
                stage=StageSizingInput(
                    pout_dbm=input.suite_pout(),
                    pae_pct=input.suite_pae(),
                    vdd_v=input.suite_vdd(),
                ),
                freq_ghz=input.suite_frequency(),
                topology=input.suite_topology(),
                er=input.suite_er(),
                h_mm=input.suite_h(),
            )
            design = transistor_design_suite(
                request.stage, request.freq_ghz, request.topology, request.er, request.h_mm
            )
        except (ValueError, OverflowError) as exc:
            logger.warning("Full-stage sizing rejected: %s", exc)
            return ui.p(f"Full-stage sizing rejected: {exc}", role="alert")
        groups = [
            (
                "Optimum load",
                design["ropt"],
                [
                    ("Ropt_ohm", "Ropt", "ohm"),
                ],
            ),
            (
                "Gate sizing",
                design["gate_width"],
                [
                    ("gate_width_mm", "Gate width", "mm"),
                ],
            ),
            ("Bias", design["idq"], [("Idq_mA", "Quiescent current", "mA")]),
            (
                "Input match",
                design["matching_input"],
                [
                    ("topology", "Matching topology", ""),
                    ("Q", "Loaded Q", "dimensionless"),
                    ("L_nH", "Inductance", "nH"),
                    ("C_pF", "Capacitance", "pF"),
                    ("bw_pct", "Legacy bandwidth estimate", "%"),
                ],
            ),
            (
                "Doherty sizing",
                design["doherty"],
                [
                    ("Ropt_peak_ohm", "Peak Ropt", "ohm"),
                    ("gate_ratio", "Peak/main gate ratio", "dimensionless"),
                ],
            ),
            (
                "Doherty combiner",
                design["combiner"],
                [
                    ("Zt_ohm", "Combiner impedance", "ohm"),
                    ("len_mm", "Combiner length", "mm"),
                    ("width_mm", "Combiner width", "mm"),
                ],
            ),
        ]
        rows = []
        for group, values, fields in groups:
            if values is None:
                rows.append(
                    ui.tags.tr(ui.tags.th(group, scope="row"), ui.tags.td("Not applicable"))
                )
                continue
            for key, label, unit in fields:
                value = values[key]
                text = (
                    "Not required"
                    if value is None
                    else f"{value:.3f} {unit}".strip()
                    if isinstance(value, (int, float))
                    else str(value)
                )
                rows.append(ui.tags.tr(ui.tags.th(label, scope="row"), ui.tags.td(text)))
        return ui.div(
            ui.p(
                f"Model: {design['model_version']} | Topology: {design['topology']} | "
                f"Target: {design['pout_dbm']:.3f} dBm | Frequency: {design['freq_ghz']:.3f} GHz"
            ),
            ui.div(
                ui.tags.table(
                    ui.tags.caption("Full-stage transistor sizing results"),
                    ui.tags.tbody(*rows),
                ),
                class_="table-scroll",
            ),
            ui.tags.ul(*(ui.tags.li(note) for note in design["limitations"])),
            ui.p("Not a device-model, stability, thermal or EM qualification."),
        )

    @render.ui
    def download_control() -> ui.Tag:
        if prepared():
            return ui.download_button("download_document", "Download lineup JSON")
        return ui.tags.button("Prepare a JSON download first", disabled=True, class_="btn")

    @render.download_button(filename="pa_lineup_python.json", media_type="application/json")
    def download_document() -> Iterator[str]:
        if not prepared():
            raise ValueError("Prepare a fresh JSON download from the canvas toolbar first")
        point = OperatingPoint(
            input_power_dbm=input.input_power_dbm(),
            backoff_db=input.backoff_db(),
            architecture=input.architecture(),
            use_canvas_operating_points=input.use_canvas_operating_points(),
        )
        yield serialize_document(with_operating_point(document(), point))


def create_app() -> App:
    for resource in (CANVAS_ROOT / "pa_lineup_canvas.js", D3_ROOT / "d3.min.js"):
        if not resource.is_file():
            raise FileNotFoundError(
                f"Required browser asset missing: {resource}. "
                "Run npm ci in python_app and use the repository checkout."
            )
    return App(
        app_ui,
        server,
        static_assets={
            "/migration": PACKAGE_ROOT / "www",
            "/legacy": CANVAS_ROOT,
            "/vendor": D3_ROOT,
        },
    )


app = create_app()
