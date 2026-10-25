from __future__ import annotations

import asyncio
import json
import logging
import sqlite3
from collections.abc import Iterator
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationError
from shiny import App, Inputs, Outputs, Session, reactive, render, ui

from rfview.cad_ui import cad_layout_preview
from rfview.domain.alps_mdf import ALPS_PLANES, AlpsPlane
from rfview.domain.cad import (
    CADDesign,
    CADHistory,
    cad_dimensions,
    parse_cad_design,
    remove_cad_component,
    update_cad_dimensions,
    update_cad_option,
    update_cad_placement,
)
from rfview.domain.component_properties import (
    ComponentGeometry,
    display_options,
    property_fields,
    text_fields,
    validated_design_properties,
    validated_properties,
    validated_visual_properties,
    visual_fields,
)
from rfview.domain.guardrails import DeviceParameters, validate_device_params
from rfview.domain.lineup import calculate_lineup
from rfview.domain.loadpull import (
    CST_WAVE_NORMALIZATIONS,
    CstWaveNormalization,
    LoadPullData,
    LoadPullFormat,
)
from rfview.domain.loadpull_contours import METRICS, LoadPullMetric
from rfview.domain.models import CanvasWorkspace, LineupDocument, LineupResult, OperatingPoint
from rfview.domain.reliability import LifetimeInputs, lifetime_estimate, reliability_curve
from rfview.domain.touchstone import (
    TouchstoneData,
    serialize_converted_parameters,
    serialize_touchstone,
    transform_network_basis,
)
from rfview.domain.transistor import (
    DesignTopology,
    StageSizingInput,
    gate_width,
    ropt,
    transistor_design_suite,
)
from rfview.knowledge_base import (
    CatalogDevice,
    DeviceReference,
    DeviceSearch,
    device_reference,
    load_device_catalog,
    search_devices,
)
from rfview.loadpull_ui import MAX_LOADPULL_VIEW_POINTS, loadpull_panel, sweep_choices
from rfview.project_store import ProjectSnapshot, ProjectStore, SavedProject, default_project_path
from rfview.services import (
    example_document,
    operating_point,
    read_alps_mdf,
    read_cad_design,
    read_document,
    read_guardrails,
    read_loadpull,
    read_spl_plan,
    read_touchstone,
    read_workspace,
    serialize_document,
    serialize_workspace,
    with_operating_point,
)
from rfview.technology_ui import Trace, line_chart, technology_panel
from rfview.touchstone_ui import MAX_VIEWER_FREQUENCIES, touchstone_panel
from rfview.workspace_ui import workspace_comparison

logger = logging.getLogger(__name__)
PACKAGE_ROOT = Path(__file__).resolve().parent
PYTHON_ROOT = PACKAGE_ROOT.parents[1]
REPOSITORY_ROOT = PYTHON_ROOT.parent
CANVAS_ROOT = REPOSITORY_ROOT / "PA design App" / "assets" / "js" / "common"
D3_ROOT = PYTHON_ROOT / "node_modules" / "d3" / "dist"
DEVICE_KB_ROOT = REPOSITORY_ROOT / "PA design App" / "data" / "kb"
GUARDRAILS = read_guardrails(
    REPOSITORY_ROOT / "PA design App" / "config" / "technology_guardrails.yaml"
)


class BrowserAction(BaseModel):
    action: str
    document: LineupDocument
    request_id: int
    workspace: CanvasWorkspace | None = None
    target_slot: Literal["1", "2", "3", "4"] | None = None


class CanvasReplacement(BaseModel):
    slot: Literal["1", "2", "3", "4"]
    expected: LineupDocument
    document: LineupDocument


class SizingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    stage: StageSizingInput
    freq_ghz: float = Field(gt=0)
    topology: DesignTopology
    er: float = Field(ge=1)
    h_mm: float = Field(gt=0)


class LifetimeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    inputs: LifetimeInputs
    horizon_hours: float = Field(gt=0, le=1e12)


def toolbar_button(identifier: str, label: str) -> ui.Tag:
    return ui.tags.button(label, id=identifier, type="button", class_="btn btn-default")


app_ui = ui.page_fluid(
    ui.tags.head(
        ui.tags.link(rel="stylesheet", href="migration/migration.css"),
        ui.tags.script(src="vendor/d3.min.js"),
        ui.tags.script(src="migration/canvas_adapter.js"),
        ui.tags.script(src="migration/cad_preview.js"),
    ),
    ui.tags.header(
        ui.h1("RF PA Design - Python"),
        ui.p(
            "Migration preview - optional local single-user project snapshots. "
            "Legacy R application remains unchanged. Production authentication/RBAC, "
            "remaining RF workflows, AI agents/KB ingestion, CAD layout editing/DRC, "
            "and document builds are not ported yet.",
            class_="migration-notice",
        ),
    ),
    ui.layout_sidebar(
        ui.sidebar(
            ui.h2("Local projects"),
            ui.p(
                "Single-user only; not authenticated or encrypted. Explicit saves include "
                "all four canvases and operating-point controls, not uploaded RF datasets."
            ),
            ui.input_text("project_name", "New project name", placeholder="Design study"),
            toolbar_button("python_create_project", "Save as new project"),
            toolbar_button("python_save_project", "Save new snapshot"),
            ui.output_text("project_status"),
            ui.tags.details(
                ui.tags.summary("Open or recover local project"),
                ui.input_numeric("project_page", "Catalogue page", 1, min=1, step=1),
                ui.input_action_button("project_refresh", "List local projects"),
                ui.input_select("project_choice", "Saved project (100 per page, newest first)", {}),
                ui.input_numeric(
                    "project_revision", "Snapshot revision (0 = latest)", 0, min=0, step=1
                ),
                toolbar_button("python_open_project", "Open selected snapshot"),
                ui.p(
                    "Opening replaces all four canvases after confirmation. Undo/zoom "
                    "restart; calculations must be refreshed. Older snapshots remain saved."
                ),
            ),
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
            ui.input_file(
                "load_workspace", "Load four-canvas workspace JSON (max 5 MiB)", accept=[".json"]
            ),
            ui.output_ui("workspace_download_control"),
            ui.h2("Selected component"),
            ui.output_ui("selected_properties"),
            ui.tags.details(
                ui.tags.summary("Design metadata and geometry"),
                ui.output_ui("selected_design_properties"),
            ),
            ui.tags.details(
                ui.tags.summary("Component annotations and display"),
                ui.output_ui("selected_visual_properties"),
            ),
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
            ui.input_select("python_canvas_slot", "Active session canvas", ["1", "2", "3", "4"]),
            toolbar_button("python_workspace_snapshot", "Prepare workspace download"),
            toolbar_button("python_compare", "Compare four canvases"),
            ui.input_select(
                "python_copy_slot", "Copy active to slot", ["1", "2", "3", "4"], selected="2"
            ),
            toolbar_button("python_copy_canvas", "Copy active canvas"),
            toolbar_button("python_clear_canvas", "Clear active canvas"),
            toolbar_button("python_calculate", "Calculate in Python"),
            ui.input_select(
                "python_component_type",
                "Component to add",
                ["transistor", "matching", "splitter", "combiner", "offset_line", "termination"],
            ),
            toolbar_button("python_add", "Add component"),
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
            "Wire mode connects component ports. Prepare a fresh download after editing. "
            "Four tabbed session canvases retain separate geometry, undo histories and zoom. "
            "Operating-point controls are shared. Workspace JSON stores all four lineups, "
            "not histories, viewport zoom or uploaded RF datasets."
        ),
        ui.div(
            id="pa_lineup_canvas_container",
            role="region",
            **{"aria-label": "Interactive RF lineup canvas"},
        ),
        ui.output_text("status"),
        ui.tags.details(
            ui.tags.summary("Standalone RF-CAD JSON import / export"),
            ui.p(
                "Import, inspect and explicitly edit component placement and dimensions "
                "in standalone RF-CAD JSON. CAD data stays separate from the PA lineup canvas."
            ),
            ui.input_file("cad_upload", "Upload RF-CAD JSON (max 5 MiB)", accept=[".json"]),
            ui.output_ui("cad_status"),
            ui.output_ui("cad_history_controls"),
            ui.output_ui("cad_summary"),
            ui.input_select("cad_component", "Inspect imported component", {}),
            ui.output_code("cad_component_detail"),
            ui.output_ui("cad_placement_controls"),
            ui.p(
                "Placement, dimension and option edits have separate Apply buttons. Applying any "
                "resets all unapplied fields, as does changing selection or importing a document. "
                "Download JSON to retain applied edits; CAD is not "
                "included in local project snapshots. CAD undo/redo restores applied edits, "
                "not selection or unapplied fields. A valid import starts new CAD history."
            ),
            ui.h3("Position overview (mm)"),
            ui.p(
                "Geometry-shaped glyphs follow supported legacy drawing parameters. "
                "Select or activate a glyph to inspect it. This is an overview only: "
                "not DRC, EM or fabrication validation."
            ),
            ui.output_ui("cad_preview"),
            ui.output_ui("cad_download_control"),
        ),
        ui.output_ui("summary"),
        ui.output_ui("stage_table"),
        ui.output_ui("workspace_comparison_view"),
        ui.tags.details(
            ui.tags.summary("Load-pull measurements and contours"),
            ui.p(
                "Session-only UTF-8 ASCII adapters; explicitly choose format and efficiency "
                "units before importing. Generic adapters: max 5 MiB / 2,000 viewer points. "
                "ALPS typed MDF: streamed up to 64 MiB; explicitly selected block only. "
                "SPL power-sweep plans: selected frequency section only, within 5 MiB. "
                "Numeric/block variants are qualified, not every vendor revision."
            ),
            ui.input_select(
                "loadpull_format",
                "Load-pull adapter",
                {
                    name: name.upper()
                    for name in (
                        "spl",
                        "focus",
                        "lpcwave",
                        "mdf",
                        "amcad",
                        "anteverta",
                        "mdif",
                        "cst",
                        "alps_mdf",
                        "spl_plan",
                    )
                },
            ),
            ui.input_checkbox(
                "loadpull_fractional",
                "Imported efficiencies are fractions (0-1), not percent",
                False,
            ),
            ui.panel_conditional(
                "input.loadpull_format === 'cst'",
                ui.input_select(
                    "loadpull_cst_normalization",
                    "CST wave normalization (confirm instrument units)",
                    CST_WAVE_NORMALIZATIONS,
                ),
                ui.input_select(
                    "loadpull_cst_block",
                    "CST power-sweep block",
                    {"1": "1 (import once to discover blocks)"},
                ),
                ui.p(
                    "Only the selected block is loaded/exported; all blocks are validated. "
                    "Raw complex waves, port references and DC quantities are retained in JSON. "
                    "No wave normalization or calibration is inferred from file extension. "
                    "Negative net powers are preserved, not clipped. Harmonic records "
                    "are rejected rather than mixed with fundamental power."
                ),
            ),
            ui.panel_conditional(
                "input.loadpull_format === 'spl_plan'",
                ui.input_select(
                    "loadpull_spl_section",
                    "SPL plan frequency section",
                    {"1": "1 (import once to discover frequency sections)"},
                ),
                ui.p(
                    "Fundamental-only SPL power-sweep-plan profile. Eff_col is drain "
                    "efficiency (%); PAE uses Pin_avail_dBm, Pout_dBm and Vout_v*Iout_mA. "
                    "Eff_%, Pdis, PoutW and quiescent bias stay separate in JSON export. "
                    "All sections and declared slots are checked; only VALID=1 rows from "
                    "the chosen section are loaded. Reimport to change frequency. "
                    "Use SPL for the existing generic table dialect."
                ),
            ),
            ui.panel_conditional(
                "input.loadpull_format === 'alps_mdf'",
                ui.input_select("loadpull_alps_plane", "ALPS Gamma reference plane", ALPS_PLANES),
                ui.input_select(
                    "loadpull_alps_selection",
                    "ALPS measurement subset",
                    {
                        "block": "Power sweep at one load block",
                        "backoff": "Load-pull across blocks at a fixed BO (dB)",
                    },
                ),
                ui.panel_conditional(
                    "input.loadpull_alps_selection === 'backoff'",
                    ui.input_numeric("loadpull_alps_backoff", "BO column value (dB)", 0, step=0.1),
                    ui.p("Match source BO within 1e-8 dB, not nearest-neighbour interpolation."),
                ),
                ui.panel_conditional(
                    "input.loadpull_alps_selection === 'block'",
                    ui.input_select(
                        "loadpull_alps_block",
                        "ALPS block to load",
                        {"1": "1 (import once to discover the block catalogue)"},
                    ),
                ),
                ui.p(
                    "Fixed ALPS measurement profile: Pin_avail_dBm, Pout_dBm, Gt_dB, Freq, "
                    "Eff_col (%), Vout_v and Iout_mA. Compression and alternative columns "
                    "remain in the selected-block JSON export. Reimport to change block/plane. "
                    "The first scan can take several seconds."
                ),
            ),
            ui.input_file(
                "loadpull_upload",
                "Upload load-pull ASCII",
                accept=[".spl", ".focus", ".lpcwave", ".mdf", ".csv", ".mdif", ".cst", ".txt"],
            ),
            ui.input_action_button("loadpull_import", "Import / reparse with selected options"),
            ui.output_text("loadpull_status"),
            ui.input_select("loadpull_sweep", "Measurement sweep", {}),
            ui.input_select(
                "loadpull_metric",
                "Load-pull metric",
                {key: f"{label} ({unit})" for key, (label, unit) in METRICS.items()},
            ),
            ui.input_checkbox(
                "loadpull_show_contours", "Show interpolated contour estimates", False
            ),
            ui.output_ui("loadpull_view"),
            ui.output_ui("loadpull_download_control"),
        ),
        ui.tags.details(
            ui.tags.summary("Touchstone magnitude and phase viewer"),
            ui.p(
                "Session-only Touchstone 1.x/2.0 viewer (.s1p-.s9p/.ts), max 5 MiB and "
                "2,000 frequencies. Uploads are not saved in lineup JSON."
            ),
            ui.input_file(
                "touchstone_upload",
                "Upload Touchstone",
                accept=[*(f".s{i}p" for i in range(1, 10)), ".ts"],
            ),
            ui.input_select("touchstone_parameter", "S-parameter", ["S11", "S21", "S12", "S22"]),
            ui.input_select(
                "touchstone_basis",
                "Analysis basis (source download stays unchanged)",
                {
                    "source": "As declared in source",
                    "single_ended": "Transform to physical single-ended port order",
                    "mixed": "Transform to explicit mixed-mode order",
                },
            ),
            ui.panel_conditional(
                "input.touchstone_basis === 'mixed'",
                ui.input_text(
                    "touchstone_modes", "Mode order (one descriptor per dimension)", "D1,2 C1,2"
                ),
                ui.p("Examples: D1,2 C1,2 or D1,2 S3 C1,2. Paired port references must be equal."),
            ),
            ui.p(
                "Basis changes use orthonormal power-wave transforms with differential 2R/"
                "common R/2 references. No impedance renormalization or noise-parameter "
                "basis conversion. Invalid transforms reject the entire derived view/export."
            ),
            ui.input_select(
                "touchstone_representation",
                "Network view (parameter selector supplies row/column indices)",
                {
                    "S": "S magnitude / phase",
                    "Z": "Z real / imaginary (ohm)",
                    "Y": "Y real / imaginary (siemens)",
                    "h": "Hybrid h real / imaginary (mixed units)",
                    "ABCD": "Chain ABCD real / imaginary (mixed units)",
                    "T": "Scattering transfer T (dimensionless)",
                    "Smith": "Smith impedance chart (diagonal S)",
                    "Stability": "Two-port stability / legacy gain metrics",
                    "Circles": "Source / load stability circles",
                    "PowerGain": "Conventional power gain v2 (10 log)",
                    "Noise": "Touchstone 1.x / 2.0 noise parameters",
                },
            ),
            ui.panel_conditional(
                "input.touchstone_representation === 'Circles'",
                ui.input_select("touchstone_frequency", "Circle frequency (GHz)", {}),
            ),
            ui.output_text("touchstone_status"),
            ui.output_ui("touchstone_download_control"),
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
            ui.tags.summary("Local device knowledge base"),
            ui.p(
                "Read-only search of checked-in vendor JSON. Search runs locally; no AI, "
                "network, project data or KB writes are involved. Source and confidence "
                "labels are shown as recorded, not independently verified."
            ),
            ui.input_text("kb_query", "Search part, notes, tags or use case", ""),
            ui.input_select(
                "kb_manufacturer",
                "Manufacturer",
                {
                    "": "All manufacturers",
                    "Ampleon": "Ampleon",
                    "Guerrilla RF": "Guerrilla RF",
                    "NXP": "NXP",
                    "Qorvo": "Qorvo",
                },
            ),
            ui.input_select(
                "kb_technology",
                "Technology",
                {"": "All technologies", "GaN-SiC": "GaN-SiC", "LDMOS": "LDMOS", "Other": "Other"},
            ),
            ui.input_numeric(
                "kb_frequency_mhz",
                "Required frequency coverage (MHz; 0 disables)",
                0,
                min=0,
            ),
            ui.input_action_button("kb_search", "Search local device catalog"),
            ui.output_ui("kb_status"),
            ui.output_ui("kb_results"),
            ui.input_select("kb_device", "Selected device record", {}),
            ui.output_code("kb_device_detail"),
            ui.input_action_button(
                "attach_kb_reference", "Attach / replace selected transistor reference"
            ),
            ui.p(
                "Replaces any existing catalog reference. Attaches provenance metadata only; "
                "does not change calculation properties, datasheet assumptions or the device model."
            ),
        ),
        ui.tags.details(
            ui.tags.summary("Generic lifetime hypothesis (corrected v2)"),
            ui.p(
                "Opt-in analytical estimate, not a manufacturer lifetime model. "
                "Temperature acceleration is corrected; legacy lineup calculations are unchanged. "
                "All inputs are independent/session-only and require engineering justification."
            ),
            ui.input_numeric("lifetime_tj", "Assumed junction temperature (C)", 125),
            ui.input_numeric("lifetime_reference", "Reference temperature (C)", 125),
            ui.input_numeric("lifetime_base", "Assumed reference MTTF (hours)", 1e6, min=0),
            ui.input_numeric("lifetime_ea", "Assumed activation energy (eV)", 0.7, min=0),
            ui.input_numeric(
                "lifetime_voltage", "Normalized voltage stress (dimensionless)", 1, min=0
            ),
            ui.input_numeric(
                "lifetime_current", "Normalized current stress (dimensionless)", 1, min=0
            ),
            ui.input_numeric("lifetime_horizon", "Plot horizon (hours)", 1e6, min=0),
            ui.output_ui("lifetime_view"),
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
        "Waiting for canvas readiness. Nothing is persisted until an explicit project save."
    )
    selected: reactive.Value[int | str | None] = reactive.Value(None)
    last_serialized = reactive.Value("")
    result_input = reactive.Value("")
    comparison: reactive.Value[CanvasWorkspace | None] = reactive.Value(None)
    comparison_input = reactive.Value("")
    pending_replacement: reactive.Value[CanvasReplacement | None] = reactive.Value(None)
    prepared = reactive.Value(False)
    workspace_export: reactive.Value[str | None] = reactive.Value(None)
    cad_design: reactive.Value[CADDesign | None] = reactive.Value(None)
    cad_export: reactive.Value[str | None] = reactive.Value(None)
    cad_revision = reactive.Value(0)
    cad_history: reactive.Value[CADHistory | None] = reactive.Value(None)
    cad_status_state = reactive.Value("No standalone RF-CAD JSON document loaded.")
    network: reactive.Value[TouchstoneData | None] = reactive.Value(None)
    network_status = reactive.Value("No Touchstone dataset loaded.")
    loadpull: reactive.Value[LoadPullData | None] = reactive.Value(None)
    loadpull_status_state = reactive.Value("No load-pull dataset loaded.")
    kb_results_state: reactive.Value[tuple[CatalogDevice, ...]] = reactive.Value(())
    kb_status_state = reactive.Value("Search to read the checked-in local device catalog.")
    current_project: reactive.Value[SavedProject | None] = reactive.Value(None)
    pending_project: reactive.Value[tuple[SavedProject, ProjectSnapshot] | None] = reactive.Value(
        None
    )
    restoring_project: reactive.Value[tuple[int, SavedProject] | None] = reactive.Value(None)

    def project_store() -> ProjectStore:
        return ProjectStore(default_project_path())

    async def refresh_projects() -> None:
        value = input.project_page()
        if value is None or value < 1 or int(value) != value:
            raise ValueError("Catalogue page must be an integer >= 1")
        projects = await asyncio.to_thread(project_store().list_projects, page=int(value))
        ui.update_select(
            "project_choice",
            choices={item.id: f"{item.name} (revision {item.revision})" for item in projects},
            session=session,
        )

    @render.text
    def project_status() -> str:
        saved = current_project()
        if saved is None:
            return "No local project attached. Unsaved browser session."
        return (
            f"{saved.info.name} | head revision {saved.info.revision} | "
            f"loaded/saved snapshot {saved.snapshot_revision}. "
            "Current edits require an explicit save."
        )

    @render.ui
    def cad_status() -> ui.Tag:
        return ui.tags.p(cad_status_state(), role="status", **{"aria-live": "polite"})

    @render.ui
    def cad_summary() -> ui.Tag:
        design = cad_design()
        if design is None:
            return ui.p("Upload a supported standalone RF-CAD document to inspect its summary.")
        rows = [
            ui.tags.tr(ui.tags.th("Format version", scope="row"), ui.tags.td(design.version)),
            ui.tags.tr(
                ui.tags.th("Components", scope="row"),
                ui.tags.td(str(len(design.components))),
            ),
        ]
        if design.substrate is not None:
            for key, label in (
                ("h", "Substrate height (mm)"),
                ("er", "Relative permittivity"),
                ("tanD", "Loss tangent"),
                ("t", "Metal thickness (mm)"),
            ):
                value = getattr(design.substrate, key)
                if value is not None:
                    rows.append(
                        ui.tags.tr(ui.tags.th(label, scope="row"), ui.tags.td(f"{value:g}"))
                    )
        counts: dict[str, int] = {}
        for component in design.components:
            counts[component.type] = counts.get(component.type, 0) + 1
        for component_type, count in sorted(counts.items()):
            rows.append(
                ui.tags.tr(
                    ui.tags.th(f"{component_type} components", scope="row"),
                    ui.tags.td(str(count)),
                )
            )
        return ui.div(
            ui.tags.table(
                ui.tags.caption("RF-CAD document summary"),
                ui.tags.tbody(*rows),
            ),
            class_="table-scroll cad-import-summary",
            tabindex="0",
            role="region",
            **{"aria-label": "Imported RF-CAD document summary"},
        )

    @render.ui
    def cad_preview() -> ui.Tag:
        design = cad_design()
        if design is None:
            return ui.p("Import a CAD document to see its geometry overview.")
        selected_id = input.cad_component()
        return cad_layout_preview(design, selected_id or None)

    @reactive.effect
    @reactive.event(input.cad_preview_select)
    def _cad_preview_select() -> None:
        design = cad_design()
        identifier = input.cad_preview_select()
        if design is None or not isinstance(identifier, str):
            return
        component = next((item for item in design.components if item.id == identifier), None)
        if component is None:
            logger.warning("Ignored CAD preview selection for unknown component %r", identifier)
            return
        ui.update_select("cad_component", selected=component.id, session=session)

    @render.code
    def cad_component_detail() -> str:
        design = cad_design()
        selected_id = input.cad_component()
        if design is None or not selected_id:
            return "Import a CAD document and select a component to inspect its stored fields."
        component = next(
            (item for item in design.components if item.id == selected_id),
            None,
        )
        if component is None:
            return "The selected component is not in the current CAD document."
        return json.dumps(
            component.model_dump(mode="json", exclude_none=True),
            indent=2,
            ensure_ascii=False,
            allow_nan=False,
        )

    @render.ui
    def cad_placement_controls() -> ui.Tag:
        design = cad_design()
        identifier = input.cad_component()
        component = (
            next((item for item in design.components if item.id == identifier), None)
            if design is not None
            else None
        )
        if component is None:
            return ui.p("Select an imported CAD component to edit its placement.")
        option_controls: list[ui.Tag] = []
        if component.type == "bend90":
            miter = component.params.get("miter")
            option_controls = [
                ui.h3("Bend option"),
                ui.input_select(
                    "cad_option_miter",
                    "Bend miter",
                    {"unset": "Legacy default (enabled)", "true": "Enabled", "false": "Disabled"},
                    selected="unset" if miter is None else "true" if miter else "false",
                ),
                ui.input_action_button("cad_apply_option", "Apply CAD option"),
            ]
        elif component.type == "port":
            number = component.params.get("portNum")
            option_controls = [
                ui.h3("Port option"),
                ui.input_text(
                    "cad_option_port",
                    "Port number (1-1000 decimal digits; positive; blank removes number)",
                    str(number) if number is not None else "",
                ),
                ui.input_action_button("cad_apply_option", "Apply CAD option"),
            ]
        return ui.div(
            ui.h3("Component placement"),
            ui.p(f"Editing component: {component.id}"),
            ui.div(
                ui.input_text("cad_edit_id", "Placement form component ID", component.id),
                ui.input_text("cad_edit_revision", "CAD document revision", str(cad_revision())),
                style="display: none;",
            ),
            ui.input_text("cad_edit_name", "CAD component name", component.name),
            ui.input_numeric("cad_edit_x", "CAD origin X (mm)", component.x),
            ui.input_numeric("cad_edit_y", "CAD origin Y (mm)", component.y),
            ui.input_numeric("cad_edit_rotation", "CAD rotation (degrees)", component.rotation),
            ui.input_text("cad_edit_layer", "CAD layer identifier", component.layer),
            ui.input_action_button("cad_apply_placement", "Apply CAD placement"),
            ui.h3("Component dimensions"),
            ui.p(
                "Positive lengths in millimetres; no impedance synthesis or DRC. "
                "Vendor parameters are retained; bend and port options have separate controls."
            ),
            *[
                ui.input_numeric(
                    f"cad_dim_{key}",
                    {
                        "W": "Trace width W (mm)",
                        "L": "Length L (mm)",
                        "gap": "Coupled trace gap (mm)",
                        "drill": "Via drill diameter (mm)",
                        "pad": "Via pad diameter (mm)",
                    }[key],
                    value,
                    min=0,
                )
                for key, value in cad_dimensions(component).items()
            ],
            ui.input_action_button("cad_apply_dimensions", "Apply CAD dimensions"),
            *option_controls,
            ui.input_action_button("cad_delete_component", "Delete selected CAD component"),
            ui.p("Deletion is reversible with Undo CAD edit."),
        )

    def _cad_edit_target() -> tuple[CADDesign, str]:
        design = cad_design()
        identifier = input.cad_component()
        if (
            design is None
            or not identifier
            or input.cad_edit_id() != identifier
            or input.cad_edit_revision() != str(cad_revision())
        ):
            raise ValueError("Select the component again before applying CAD edits")
        return design, identifier

    @render.ui
    def cad_history_controls() -> ui.Tag:
        history = cad_history()
        undo_count = history.undo_count if history is not None else 0
        redo_count = history.redo_count if history is not None else 0
        return ui.div(
            ui.div(
                ui.input_action_button("cad_undo", "Undo CAD edit", disabled=undo_count == 0),
                ui.input_action_button("cad_redo", "Redo CAD edit", disabled=redo_count == 0),
                class_="migration-toolbar",
            ),
            ui.p(
                f"CAD history: {undo_count} undo / {redo_count} redo. "
                "Keeps up to 20 document states / 20 MiB of UTF-8 JSON per session; "
                "oldest states are discarded at the limit.",
                role="status",
                **{"aria-live": "polite"},
            ),
        )

    def _restore_cad_state(history: CADHistory, identifier: str) -> None:
        restored = parse_cad_design(history.current_text)
        identifiers = {item.id for item in restored.components}
        if identifier not in identifiers:
            identifier = restored.components[0].id if restored.components else ""
        cad_design.set(restored)
        cad_export.set(history.current_text)
        cad_history.set(history)
        cad_revision.set(cad_revision() + 1)
        ui.update_select(
            "cad_component",
            choices={
                item.id: f"{item.name or item.id} · {item.type}" for item in restored.components
            },
            selected=identifier,
            session=session,
        )

    def _commit_cad_edit(updated: CADDesign, identifier: str, kind: str) -> None:
        history = cad_history()
        if history is None:
            raise ValueError("Import a CAD document before editing")
        _restore_cad_state(history.record(updated), identifier)
        cad_status_state.set(
            f"Applied {kind} for {identifier}. Download CAD JSON to retain edits. "
            "No DRC or fabrication validation performed."
        )

    def _move_cad_history(direction: Literal["undo", "redo"]) -> None:
        try:
            history = cad_history()
            if history is None:
                raise ValueError("Import a CAD document before using history")
            moved = history.undo() if direction == "undo" else history.redo()
            _restore_cad_state(moved, input.cad_component() or "")
        except (ValueError, OverflowError, RecursionError) as exc:
            message = f"RF-CAD {direction} rejected: {exc}. Last valid document retained."
            logger.warning("%s", message)
            cad_status_state.set(message)
            ui.notification_show(message, type="error", duration=None, session=session)
            return
        cad_status_state.set(
            f"CAD {direction} restored the document. Unapplied fields reset. "
            "Download CAD JSON to retain this state. No DRC or fabrication validation performed."
        )

    @reactive.effect
    @reactive.event(input.cad_undo)
    def _cad_undo() -> None:
        _move_cad_history("undo")

    @reactive.effect
    @reactive.event(input.cad_redo)
    def _cad_redo() -> None:
        _move_cad_history("redo")

    @reactive.effect
    @reactive.event(input.cad_apply_placement)
    def _cad_apply_placement() -> None:
        try:
            design, identifier = _cad_edit_target()
            updated = update_cad_placement(
                design,
                identifier,
                name=input.cad_edit_name(),
                x=input.cad_edit_x(),
                y=input.cad_edit_y(),
                rotation=input.cad_edit_rotation(),
                layer=input.cad_edit_layer(),
            )
            _commit_cad_edit(updated, identifier, "placement")
        except (ValueError, OverflowError, RecursionError) as exc:
            message = f"RF-CAD placement rejected: {exc}. Last valid document retained."
            logger.warning("%s", message)
            cad_status_state.set(message)
            ui.notification_show(message, type="error", duration=None, session=session)
            return

    @reactive.effect
    @reactive.event(input.cad_apply_dimensions)
    def _cad_apply_dimensions() -> None:
        try:
            design, identifier = _cad_edit_target()
            component = next((item for item in design.components if item.id == identifier), None)
            if component is None:
                raise ValueError("Selected component is not in the current CAD document")
            updated = update_cad_dimensions(
                design,
                identifier,
                {key: input[f"cad_dim_{key}"]() for key in cad_dimensions(component)},
            )
            _commit_cad_edit(updated, identifier, "dimensions")
        except (ValueError, OverflowError, RecursionError) as exc:
            message = f"RF-CAD dimensions rejected: {exc}. Last valid document retained."
            logger.warning("%s", message)
            cad_status_state.set(message)
            ui.notification_show(message, type="error", duration=None, session=session)

    @reactive.effect
    @reactive.event(input.cad_apply_option)
    def _cad_apply_option() -> None:
        try:
            design, identifier = _cad_edit_target()
            component = next((item for item in design.components if item.id == identifier), None)
            if component is None:
                raise ValueError("Selected component is not in the current CAD document")
            if component.type == "bend90":
                choice = input.cad_option_miter()
                if choice not in ("unset", "true", "false"):
                    raise ValueError("Select a supported bend miter option")
                updated = update_cad_option(
                    design, identifier, None if choice == "unset" else choice == "true"
                )
            elif component.type == "port":
                number = input.cad_option_port().strip()
                if number and (
                    len(number) > 1000 or not number.isascii() or not number.isdecimal()
                ):
                    raise ValueError("Port number must contain 1-1000 decimal digits, or be blank")
                updated = update_cad_option(design, identifier, int(number) if number else None)
            else:
                raise ValueError("Only bends and ports have editable CAD options")
            _commit_cad_edit(updated, identifier, "option")
        except (ValueError, OverflowError, RecursionError) as exc:
            message = f"RF-CAD option rejected: {exc}. Last valid document retained."
            logger.warning("%s", message)
            cad_status_state.set(message)
            ui.notification_show(message, type="error", duration=None, session=session)

    @reactive.effect
    @reactive.event(input.cad_delete_component)
    def _cad_delete_component() -> None:
        try:
            design, identifier = _cad_edit_target()
            updated = remove_cad_component(design, identifier)
            _commit_cad_edit(updated, identifier, "deletion")
        except (ValueError, OverflowError, RecursionError) as exc:
            message = f"RF-CAD deletion rejected: {exc}. Last valid document retained."
            logger.warning("%s", message)
            cad_status_state.set(message)
            ui.notification_show(message, type="error", duration=None, session=session)

    @render.ui
    def cad_download_control() -> ui.Tag:
        if cad_export() is None:
            return ui.p("Import a valid RF-CAD document to enable normalized JSON export.")
        return ui.div(
            ui.download_button("download_cad", "Download normalized RF-CAD JSON"),
            ui.p(
                "Unknown document properties are retained. This is a normalized JSON "
                "interchange, not a renderer, DRC or EM-analysis result."
            ),
        )

    @render.download_button(filename="rf_cad_design.json", media_type="application/json")
    def download_cad() -> Iterator[str]:
        serialized = cad_export()
        if serialized is None:
            raise ValueError("No RF-CAD document is available to export")
        yield serialized

    @reactive.effect
    @reactive.event(input.cad_upload)
    async def _cad_upload() -> None:
        files = input.cad_upload()
        if not files:
            return
        try:
            design = await asyncio.to_thread(read_cad_design, Path(files[0]["datapath"]))
            history = CADHistory.from_design(design)
        except (OSError, ValueError, ValidationError, RecursionError) as exc:
            message = f"RF-CAD import rejected: {exc}. Last valid document retained."
            logger.warning("%s", message)
            cad_status_state.set(message)
            ui.notification_show(message, type="error", duration=None, session=session)
            return
        _restore_cad_state(history, design.components[0].id if design.components else "")
        cad_status_state.set(
            f"Imported {files[0]['name']}: {len(design.components)} component(s), "
            "validated for normalized JSON export. Session-only."
        )

    @render.ui
    def kb_status() -> ui.Tag:
        return ui.tags.p(kb_status_state(), role="status", **{"aria-live": "polite"})

    @render.ui
    def kb_results() -> ui.Tag:
        items = kb_results_state()
        if not items:
            return ui.p("No matching records. Search or change the filters.")

        cards: list[ui.Tag] = []
        for item in items:
            record = item.record
            band = f"{record.freq_min_mhz:g}-{record.freq_max_mhz:g} MHz"
            power = []
            if record.pout_w_cw is not None:
                power.append(f"{record.pout_w_cw:g} W CW")
            if record.pout_w_pulse is not None:
                power.append(f"{record.pout_w_pulse:g} W pulse")
            cards.append(
                ui.tags.article(
                    ui.tags.h4(f"{record.part_number} · {record.manufacturer}"),
                    ui.tags.p(f"{record.technology} · {band}"),
                    ui.tags.p(" / ".join(power) if power else "No CW/pulse rating recorded."),
                    ui.tags.p(
                        f"Source: {record.knowledge_source or 'not recorded'} · "
                        f"confidence label: {record.knowledge_confidence or 'not recorded'} · "
                        f"lifecycle: {record.status or 'not recorded'}"
                    ),
                    class_="kb-device-card",
                )
            )
        return ui.div(*cards, class_="kb-device-results")

    @render.code
    def kb_device_detail() -> str:
        identifier = input.kb_device()
        for item in kb_results_state():
            if item.record.device_id == identifier:
                payload = {
                    "record": item.record.model_dump(mode="json", exclude_none=True),
                    "catalog_source_file": item.source_file,
                    "catalog_source_sha256": item.source_sha256,
                }
                return json.dumps(payload, indent=2, ensure_ascii=False, allow_nan=False)
        return "Search the catalog and select a matching record to inspect its stored fields."

    @reactive.effect
    @reactive.event(input.kb_search)
    async def _search_local_device_catalog() -> None:
        try:
            raw_frequency = input.kb_frequency_mhz()
            criteria = DeviceSearch(
                query=input.kb_query() or "",
                manufacturer=input.kb_manufacturer() or None,
                technology=input.kb_technology() or None,
                frequency_mhz=(
                    raw_frequency if raw_frequency is not None and raw_frequency > 0 else None
                ),
                max_results=50,
            )
            catalog = await asyncio.to_thread(load_device_catalog, DEVICE_KB_ROOT)
            matches = search_devices(catalog, criteria)
        except (OSError, ValueError, OverflowError, RecursionError) as exc:
            kb_status_state.set(f"Local device catalog search failed: {exc}")
            failure(f"Local device catalog search failed: {exc}")
            return

        kb_results_state.set(matches.items)
        ui.update_select(
            "kb_device",
            choices={
                item.record.device_id: (
                    f"{item.record.part_number} — {item.record.manufacturer} "
                    f"({item.record.technology})"
                )
                for item in matches.items
            },
            selected=matches.items[0].record.device_id if matches.items else "",
            session=session,
        )
        note = f"Found {matches.total_matches} matching record(s); showing {len(matches.items)}."
        if matches.truncated:
            note += " Narrow the search to show other matches."
        sources = sorted({item.source_file for item in catalog})
        kb_status_state.set(
            f"{note} Read-only local sources: {', '.join(sources)}. "
            "Source/confidence labels are not an engineering qualification."
        )

    @reactive.effect
    @reactive.event(input.attach_kb_reference)
    async def _attach_kb_reference() -> None:
        component = next(
            (item for item in document().components if str(item.id) == str(selected())), None
        )
        item = next(
            (
                record
                for record in kb_results_state()
                if record.record.device_id == input.kb_device()
            ),
            None,
        )
        try:
            if component is None or component.type != "transistor":
                raise ValueError("Select a transistor on the active canvas first")
            if item is None:
                raise ValueError("Search and select a device record from the local catalog first")
            reference = device_reference(item)
        except (ValueError, ValidationError) as exc:
            failure(f"Device reference attachment rejected: {exc}")
            return
        await session.send_custom_message(
            "pythonEditComponent",
            {
                "id": component.id,
                "properties": {
                    "kb_device_reference": reference.model_dump(mode="json", exclude_none=True)
                },
            },
        )
        status_state.set(
            f"Attached KB provenance for {reference.manufacturer} {reference.part_number}; "
            "lineup calculation properties were not changed."
        )

    @reactive.effect
    @reactive.event(input.project_refresh)
    async def _refresh_projects() -> None:
        try:
            await refresh_projects()
        except (ValueError, OverflowError, OSError, sqlite3.Error) as exc:
            failure(f"Project listing failed: {exc}")

    @reactive.effect
    @reactive.event(input.python_project_loaded)
    def _project_loaded() -> None:
        restoring = restoring_project()
        if restoring is None or input.python_project_loaded() != restoring[0]:
            failure("Unexpected project recovery acknowledgement; project not attached")
            return
        saved = restoring[1]
        current_project.set(saved)
        restoring_project.set(None)
        status_state.set(
            f"Recovered {saved.info.name}, snapshot {saved.snapshot_revision}. "
            "Recalculate before using results; save creates a new revision."
        )

    async def project_action(action: BrowserAction) -> None:
        try:
            if restoring_project() is not None:
                raise ValueError("Project recovery is still awaiting the browser acknowledgement")
            if action.workspace is None:
                raise ValueError("Project operation requires all four canvas snapshots")
            snapshot = ProjectSnapshot(
                workspace=action.workspace,
                operating_point=OperatingPoint(
                    input_power_dbm=input.input_power_dbm(),
                    backoff_db=input.backoff_db(),
                    architecture=input.architecture(),
                    use_canvas_operating_points=input.use_canvas_operating_points(),
                ),
            )
            if action.action == "open_project":
                value = input.project_revision()
                if value is None or value < 0 or int(value) != value:
                    raise ValueError("Snapshot revision must be an integer >= 0")
                saved = await asyncio.to_thread(
                    project_store().load, input.project_choice(), int(value) or None
                )
                pending_project.set((saved, snapshot))
                ui.modal_show(
                    ui.modal(
                        ui.p(
                            f"Open {saved.info.name}, snapshot {saved.snapshot_revision}? "
                            "All four current canvases and operating-point controls will be "
                            "replaced. Unsaved edits, undo history and zoom will be lost. "
                            "Imported RF datasets are not changed or restored."
                        ),
                        title="Confirm project recovery",
                        footer=ui.TagList(
                            ui.modal_button("Cancel"),
                            toolbar_button("python_confirm_project_load", "Replace workspace"),
                        ),
                        easy_close=True,
                    ),
                    session=session,
                )
                return
            if action.action == "confirm_project_load":
                pending = pending_project()
                pending_project.set(None)
                ui.modal_remove(session=session)
                if pending is None:
                    raise ValueError("Request project recovery again")
                saved, expected = pending
                if snapshot != expected:
                    raise ValueError("Workspace changed after recovery confirmation; request again")
                latest = await asyncio.to_thread(
                    project_store().load, saved.info.id, saved.snapshot_revision
                )
                if latest.info.revision != saved.info.revision:
                    raise ValueError("Project changed during confirmation; request recovery again")
                saved = latest
                snapshot = saved.snapshot
                result.set(None)
                prepared.set(False)
                comparison.set(None)
                workspace_export.set(None)
                pending_replacement.set(None)
                document.set(snapshot.workspace.canvases[snapshot.workspace.active])
                selected.set(None)
                point = snapshot.operating_point
                ui.update_numeric("input_power_dbm", value=point.input_power_dbm, session=session)
                ui.update_numeric("backoff_db", value=point.backoff_db, session=session)
                ui.update_select("architecture", selected=point.architecture, session=session)
                ui.update_checkbox(
                    "use_canvas_operating_points",
                    value=point.use_canvas_operating_points,
                    session=session,
                )
                current_project.set(None)
                restoring_project.set((action.request_id, saved))
                await session.send_custom_message(
                    "pythonLoadWorkspace",
                    {
                        **snapshot.workspace.model_dump(mode="json", by_alias=True),
                        "project_request_id": action.request_id,
                    },
                )
                return
            if action.action == "create_project":
                saved = await asyncio.to_thread(
                    project_store().create, input.project_name(), snapshot
                )
            else:
                current = current_project()
                if current is None:
                    raise ValueError("Open a local project or save as a new project first")
                saved = await asyncio.to_thread(
                    project_store().save, current.info.id, current.info.revision, snapshot
                )
            current_project.set(saved)
            status_state.set(
                f"Saved {saved.info.name}, immutable snapshot {saved.snapshot_revision}. "
                "Subsequent edits are not saved automatically."
            )
        except (ValueError, OverflowError, OSError, sqlite3.Error) as exc:
            failure(f"Project operation failed: {exc}")

    @reactive.effect
    @reactive.event(input.loadpull_import)
    async def _loadpull_import() -> None:
        files = input.loadpull_upload()
        try:
            if not files:
                raise ValueError("Choose a load-pull ASCII file first")
            adapter: LoadPullFormat = input.loadpull_format()
            if adapter == "alps_mdf":
                if input.loadpull_fractional():
                    raise ValueError("ALPS Eff_col uses percent; deselect fractional efficiencies")
                plane: AlpsPlane = input.loadpull_alps_plane()
                block_index = int(input.loadpull_alps_block())
                backoff_db = (
                    input.loadpull_alps_backoff()
                    if input.loadpull_alps_selection() == "backoff"
                    else None
                )
                if input.loadpull_alps_selection() == "backoff" and backoff_db is None:
                    raise ValueError("Enter the source BO value in dB")
                with ui.Progress(min=0, max=1, session=session) as progress:
                    progress.set(
                        message="Validating ALPS stream; retaining selected block", value=0.1
                    )
                    imported = await asyncio.to_thread(
                        read_alps_mdf,
                        Path(files[0]["datapath"]),
                        files[0]["name"],
                        plane=plane,
                        block_index=block_index,
                        backoff_db=backoff_db,
                    )
                    progress.set(value=1)
                parsed = imported.dataset
                ui.update_select(
                    "loadpull_alps_block",
                    choices={
                        str(block.index): (
                            f"{block.index}: {block.rows} rows; "
                            + ", ".join(
                                f"{key}={value:.6g}" for key, value in block.variables.items()
                            )
                        )
                        for block in imported.blocks
                    },
                    selected=str(block_index),
                    session=session,
                )
            elif adapter == "spl_plan":
                if input.loadpull_fractional():
                    raise ValueError(
                        "SPL plan Eff_col uses percent; deselect fractional efficiencies"
                    )
                section_index = int(input.loadpull_spl_section())
                plan = await asyncio.to_thread(
                    read_spl_plan,
                    Path(files[0]["datapath"]),
                    files[0]["name"],
                    section_index=section_index,
                )
                parsed = plan.dataset
                ui.update_select(
                    "loadpull_spl_section",
                    choices={
                        str(section.index): (
                            f"{section.index}: {section.frequency_ghz:.12g} GHz | "
                            f"{section.valid_rows} valid / {section.invalid_rows} invalid slots"
                        )
                        for section in plan.sections
                    },
                    selected=str(section_index),
                    session=session,
                )
            else:
                normalization: CstWaveNormalization = input.loadpull_cst_normalization()
                parsed = read_loadpull(
                    Path(files[0]["datapath"]),
                    files[0]["name"],
                    adapter,
                    fractional=input.loadpull_fractional(),
                    cst_wave_normalization=normalization,
                    cst_block_index=int(input.loadpull_cst_block()) if adapter == "cst" else None,
                )
                if adapter == "cst":
                    ui.update_select(
                        "loadpull_cst_block",
                        choices={
                            str(index): f"{index}: {parsed.metadata[f'block_{index}']}"
                            for index in range(1, int(parsed.metadata["total_blocks"]) + 1)
                        },
                        selected=parsed.metadata["selected_block"],
                        session=session,
                    )
            if len(parsed.points) > MAX_LOADPULL_VIEW_POINTS:
                raise ValueError(f"Viewer limit is {MAX_LOADPULL_VIEW_POINTS} load-pull points")
        except (ValueError, OSError) as exc:
            message = f"Load-pull import rejected: {exc}. Last valid dataset retained."
            logger.warning("%s", message)
            loadpull_status_state.set(message)
            ui.notification_show(message, type="error", duration=None, session=session)
            return
        loadpull.set(parsed)
        ui.update_select(
            "loadpull_sweep", choices=sweep_choices(parsed), selected="sweep-0", session=session
        )
        scope = (
            f" {parsed.metadata['selection']}; "
            f"{len(parsed.points)}/{parsed.metadata['total_source_rows']} source rows. "
            f"{parsed.metadata['gamma_plane']}."
            if adapter == "alps_mdf"
            else ""
        )
        if adapter == "spl_plan":
            scope = (
                f" Section {parsed.metadata['selected_section']}/"
                f"{parsed.metadata['total_sections']} at "
                f"{float(parsed.metadata['frequency_ghz']):.12g} GHz; "
                f"{len(parsed.points)} valid measurements, "
                f"{parsed.metadata['selected_invalid_rows']} VALID=0 slots excluded. "
                f"All {parsed.metadata['total_source_slots']} source slots checked."
            )
        elif adapter == "cst":
            scope = (
                f" Block {parsed.metadata['selected_block']}/{parsed.metadata['total_blocks']}; "
                f"{len(parsed.points)}/{parsed.metadata['total_source_rows']} source rows. "
                f"Wave normalization: {parsed.metadata['wave_normalization']}."
            )
        loadpull_status_state.set(
            f"Loaded {parsed.filename} using {parsed.format}.{scope} Session-only."
        )

    @render.text
    def loadpull_status() -> str:
        return loadpull_status_state()

    @render.ui
    def loadpull_view() -> ui.Tag:
        current = loadpull()
        if current is None:
            return ui.p("Choose an adapter and file, then import measurements.")
        try:
            metric: LoadPullMetric = input.loadpull_metric()
            return loadpull_panel(
                current, input.loadpull_sweep(), metric, input.loadpull_show_contours()
            )
        except ValueError as exc:
            logger.warning("Load-pull view rejected: %s", exc)
            return ui.p(f"Load-pull view rejected: {exc}", role="alert")

    @render.ui
    def loadpull_download_control() -> ui.Tag:
        if loadpull() is None:
            return ui.p("Import measurements to enable normalized JSON export.")
        return ui.div(
            ui.download_button("download_loadpull", "Download normalized load-pull JSON"),
            ui.p(
                "Contains all normalized points, metadata and warnings, "
                "not a vendor-format round trip."
            ),
        )

    @render.download(filename="rfview_loadpull.json", media_type="application/json")
    def download_loadpull() -> Iterator[str]:
        current = loadpull()
        if current is None:
            raise ValueError("No load-pull dataset available")
        yield current.model_dump_json(indent=2)

    @reactive.effect
    @reactive.event(input.touchstone_upload)
    def _touchstone_upload() -> None:
        files = input.touchstone_upload()
        if not files:
            return
        try:
            parsed = read_touchstone(Path(files[0]["datapath"]), filename=files[0]["name"])
            if max(len(parsed.freq_ghz), len(parsed.noise)) > MAX_VIEWER_FREQUENCIES:
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
        ui.update_select("touchstone_basis", selected="source", session=session)
        choices = list(dict.fromkeys(p.param for p in parsed.points[: parsed.nports**2]))
        ui.update_select("touchstone_parameter", choices=choices, selected="S11", session=session)
        ui.update_select(
            "touchstone_frequency",
            choices={str(i): f"{freq:.12g}" for i, freq in enumerate(parsed.freq_ghz)},
            selected="0",
            session=session,
        )
        network_status.set(f"Loaded {parsed.filename}. Session-only; no dataset saved.")

    @render.text
    def touchstone_status() -> str:
        return network_status()

    @reactive.calc
    def analysis_network() -> TouchstoneData:
        current = network()
        if current is None:
            raise ValueError("No Touchstone dataset available")
        basis = input.touchstone_basis()
        if basis == "source":
            return current
        if basis == "single_ended":
            return transform_network_basis(current)
        if basis == "mixed":
            return transform_network_basis(current, tuple(input.touchstone_modes().split()))
        raise ValueError("Choose a supported analysis basis")

    @reactive.calc
    def converted_csv() -> str:
        return serialize_converted_parameters(analysis_network(), input.touchstone_representation())

    @render.ui
    def touchstone_download_control() -> ui.Tag:
        if network() is None:
            return ui.p("Upload a dataset to enable source Touchstone export.")
        basis_control: ui.Tag = ui.p("Source basis selected; no transformed dataset requested.")
        if input.touchstone_basis() != "source":
            try:
                analysis_network()
                basis_control = ui.download_button(
                    "download_transformed_network", "Download transformed S (Touchstone 2.0)"
                )
            except ValueError as exc:
                logger.warning("Basis transform rejected: %s", exc)
                basis_control = ui.p(f"Transformed export unavailable: {exc}", role="alert")
        converted_control: ui.Tag = ui.p("Select Z/Y/h/ABCD/T to export converted parameters.")
        if input.touchstone_representation() in ("Z", "Y", "h", "ABCD", "T"):
            try:
                converted_csv()
                converted_control = ui.download_button(
                    "download_network_csv", "Download converted family CSV"
                )
            except ValueError as exc:
                logger.warning("Converted network export rejected: %s", exc)
                converted_control = ui.p(f"Converted export unavailable: {exc}", role="alert")
        return ui.div(
            ui.download_button("download_touchstone", "Download source S (GHz / RI)"),
            ui.p(
                "Exports source S values, not the selected converted view. "
                "Original comments, units and formatting are not retained. "
                "Touchstone 2.0/per-port references are retained when present."
            ),
            converted_control,
            basis_control,
            ui.p(
                "Converted CSV contains all four parameters at every frequency, "
                "real/imaginary values, units and source port references; "
                "not just the selected trace."
            ),
        )

    def touchstone_filename() -> str:
        current = network()
        if current is None:
            raise ValueError("No Touchstone dataset available for export")
        return f"rfview_source.s{current.nports}p"

    @render.download(filename=touchstone_filename, media_type="text/plain")
    def download_touchstone() -> Iterator[str]:
        current = network()
        if current is None:
            raise ValueError("No Touchstone dataset available for export")
        yield serialize_touchstone(current)

    @render.download(filename="rfview_converted_network.csv", media_type="text/csv")
    def download_network_csv() -> Iterator[str]:
        yield converted_csv()

    @render.download(filename="rfview_transformed.ts", media_type="text/plain")
    def download_transformed_network() -> Iterator[str]:
        yield serialize_touchstone(analysis_network())

    @render.ui
    def touchstone_view() -> ui.Tag:
        current = network()
        if current is None:
            return ui.p("Upload a supported Touchstone file to view its magnitude and phase.")
        parameter = input.touchstone_parameter()
        if current.nports == 1 and parameter != "S11":
            return ui.p("Updating parameter selection for the one-port dataset.")
        try:
            current = analysis_network()
            choice = input.touchstone_frequency()
            if input.touchstone_representation() == "Circles" and not choice:
                return ui.p("Choose an available circle frequency.")
            return ui.div(
                ui.p(f"Analysis basis: {input.touchstone_basis()}; source values are preserved."),
                touchstone_panel(
                    current,
                    parameter,
                    input.touchstone_representation(),
                    int(choice) if choice else 0,
                ),
            )
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
        comparison.set(None)
        document.set(new_document)
        result.set(None)
        selected.set(None)
        prepared.set(False)
        workspace_export.set(None)
        await session.send_custom_message(
            "pythonLoadConfiguration", new_document.model_dump(mode="json", by_alias=True)
        )

    @reactive.effect
    @reactive.event(input.python_canvas_ready)
    async def _ready() -> None:
        await load_canvas(document())
        status_state.set("Python canvas ready. Load/edit a lineup and calculate; R is not used.")

    @reactive.effect
    @reactive.event(input.python_slot_changed)
    def _slot_changed() -> None:
        comparison.set(None)
        result.set(None)
        selected.set(None)
        prepared.set(False)
        workspace_export.set(None)
        status_state.set("Active canvas changed. Operating-point controls are shared; recalculate.")

    @reactive.effect
    @reactive.event(input.load_workspace)
    async def _load_workspace() -> None:
        files = input.load_workspace()
        if not files:
            return
        try:
            workspace = read_workspace(Path(files[0]["datapath"]))
        except (ValueError, OSError) as exc:
            failure(f"Workspace load rejected: {exc}. Current canvases retained.")
            return
        document.set(workspace.canvases[workspace.active])
        comparison.set(None)
        result.set(None)
        selected.set(None)
        prepared.set(False)
        workspace_export.set(None)
        await session.send_custom_message(
            "pythonLoadWorkspace", workspace.model_dump(mode="json", by_alias=True)
        )
        status_state.set("Workspace loaded. Four lineups restored; undo histories restart.")

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
        restoring_project.set(None)
        failure(f"Canvas error: {input.python_canvas_error()}")

    @reactive.effect
    @reactive.event(input.python_snapshot)
    def _snapshot() -> None:
        comparison.set(None)
        workspace_export.set(None)
        try:
            snapshot = LineupDocument.model_validate_json(json.dumps(input.python_snapshot()))
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
            action = BrowserAction.model_validate_json(json.dumps(input.python_action()))
            if action.action in (
                "create_project",
                "save_project",
                "open_project",
                "confirm_project_load",
            ):
                await project_action(action)
                return
            document.set(action.document)
            last_serialized.set(serialize_document(action.document))
            if action.action in ("clone_slot", "clear_slot"):
                if action.workspace is None:
                    raise ValueError("Workspace snapshot is missing")
                source = action.workspace.active
                target = action.target_slot if action.action == "clone_slot" else source
                if target is None or (action.action == "clone_slot" and target == source):
                    raise ValueError("Copy requires a different target slot")
                replacement = CanvasReplacement(
                    slot=target,
                    expected=action.workspace.canvases[target],
                    document=action.document.model_copy(deep=True)
                    if action.action == "clone_slot"
                    else LineupDocument(components=[]),
                )
                pending_replacement.set(replacement)
                ui.modal_show(
                    ui.modal(
                        ui.p(
                            f"Replace canvas {target}? Other canvases are retained. "
                            "The replaced slot's undo history and zoom will restart. "
                            "Download a workspace first if you need to preserve it."
                        ),
                        title="Confirm canvas replacement",
                        footer=ui.TagList(
                            ui.modal_button("Cancel"),
                            ui.input_action_button("confirm_canvas_replace", "Replace canvas"),
                        ),
                        easy_close=True,
                    ),
                    session=session,
                )
                return
            if action.action == "compare_workspace":
                if action.workspace is None:
                    raise ValueError("Workspace snapshot is missing")
                comparison.set(action.workspace)
                comparison_input.set(_parameters())
                status_state.set("Four-canvas comparison prepared from current documents.")
                return
            if action.action == "workspace_snapshot":
                workspace_export.set(None)
                if action.workspace is None:
                    raise ValueError("Workspace snapshot is missing")
                workspace_export.set(serialize_workspace(action.workspace))
                status_state.set(
                    "Workspace snapshot prepared. Download all four lineups from the sidebar."
                )
                return
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

    @reactive.effect
    @reactive.event(input.confirm_canvas_replace)
    async def _confirm_replace() -> None:
        replacement = pending_replacement()
        pending_replacement.set(None)
        ui.modal_remove(session=session)
        if replacement is None:
            failure("Canvas replacement expired. Request a new replacement.")
            return
        comparison.set(None)
        workspace_export.set(None)
        prepared.set(False)
        result.set(None)
        await session.send_custom_message(
            "pythonReplaceSlot", replacement.model_dump(mode="json", by_alias=True)
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

    @render.ui
    def workspace_comparison_view() -> ui.Tag:
        current = comparison()
        if current is None or comparison_input() != _parameters():
            return ui.p("Compare four canvases to view a fresh simultaneous snapshot.")
        return workspace_comparison(
            current,
            OperatingPoint(
                input_power_dbm=input.input_power_dbm(),
                backoff_db=input.backoff_db(),
                architecture=input.architecture(),
                use_canvas_operating_points=input.use_canvas_operating_points(),
            ),
        )

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
    def lifetime_view() -> ui.Tag:
        try:
            request = LifetimeRequest.model_validate(
                {
                    "inputs": {
                        "tj_c": input.lifetime_tj(),
                        "reference_c": input.lifetime_reference(),
                        "base_hours": input.lifetime_base(),
                        "activation_ev": input.lifetime_ea(),
                        "voltage_stress": input.lifetime_voltage(),
                        "current_stress": input.lifetime_current(),
                    },
                    "horizon_hours": input.lifetime_horizon(),
                }
            )
            result = lifetime_estimate(request.inputs)
            curve = reliability_curve(
                [request.horizon_hours * i / 100 for i in range(101)], result.mttf_hours
            )
        except ValueError as exc:
            logger.warning("Lifetime hypothesis rejected: %s", exc)
            return ui.p(f"Lifetime hypothesis rejected: {exc}", role="alert")
        return ui.div(
            ui.p(
                f"Model: {result.model_version} | MTTF: {result.mttf_hours:.6g} hours | "
                f"{result.mttf_years:.6g} years | "
                f"Failure rate: {result.failure_rate_per_hour:.6g} /hour"
            ),
            ui.tags.ul(*(ui.tags.li(message) for message in result.warnings)),
            line_chart(
                "Generic constant-hazard reliability estimate",
                "Time (hours)",
                "Reliability (%)",
                [Trace("Generic hypothesis, not qualification", list(curve), "#ff7f11")],
            ),
        )

    @render.ui
    def selected_properties() -> ui.Tag:
        component = next(
            (item for item in document().components if str(item.id) == str(selected())), None
        )
        if component is None:
            return ui.p("Select a component on the canvas.")
        try:
            fields = property_fields(component)
            controls = [
                ui.input_numeric(
                    f"edit_{field.key}", field.label, component.number(field.key, field.default)
                )
                for field in fields
            ]
        except ValueError as exc:
            logger.warning("Component properties rejected: %s", exc)
            return ui.p(f"Component properties rejected: {exc}", role="alert")
        if component.type == "termination":
            return ui.p("Termination: no editable calculation inputs in the legacy model.")
        reference_panel: ui.Tag | None = None
        raw_reference = component.properties.get("kb_device_reference")
        if raw_reference is not None:
            try:
                reference = DeviceReference.model_validate(raw_reference)
                reference_panel = ui.tags.section(
                    ui.tags.h4("Attached catalog reference (provenance only)"),
                    ui.tags.p(
                        f"{reference.manufacturer} {reference.part_number} — "
                        f"{reference.technology}, {reference.freq_min_mhz:g}-"
                        f"{reference.freq_max_mhz:g} MHz"
                    ),
                    ui.tags.p(
                        f"Recorded source: {reference.knowledge_source or 'not recorded'}; "
                        "confidence: "
                        f"{reference.knowledge_confidence or 'not recorded'}; "
                        f"catalog file: {reference.catalog_source_file}; "
                        f"SHA-256: {reference.catalog_source_sha256}"
                    ),
                    ui.tags.p(
                        reference.datasheet_url or "No datasheet URL recorded.",
                        class_="kb-reference-url",
                    ),
                    class_="kb-device-reference",
                )
            except ValidationError as exc:
                logger.warning("Attached KB reference rejected: %s", exc)
                reference_panel = ui.p(
                    "Attached device-reference metadata is invalid; preserved without use.",
                    role="alert",
                )
        return ui.div(
            ui.p(f"Type: {component.type}. Only calculation inputs listed below are edited."),
            reference_panel,
            ui.input_text(
                "edit_component_id",
                "Editing component ID (must match selection)",
                str(component.id),
            ),
            *controls,
            ui.p(
                "Splitter/combiner branch counts come from graph connections. "
                "Unequal splitting is not implemented; topology, technology, labels and "
                "other legacy properties are retained unchanged."
            ),
            ui.input_action_button("apply_properties", "Apply component properties"),
        )

    @reactive.effect
    @reactive.event(input.apply_properties)
    async def _apply() -> None:
        component = next(
            (item for item in document().components if str(item.id) == str(selected())), None
        )
        try:
            if component is None or str(component.id) != input.edit_component_id():
                raise ValueError("Selection changed; wait for its property form before applying")
            if component.type == "termination":
                raise ValueError("Termination has no editable calculation inputs")
            properties = validated_properties(
                component,
                {field.key: input[f"edit_{field.key}"]() for field in property_fields(component)},
            )
        except ValueError as exc:
            failure(f"Property edit rejected: {exc}")
            return
        await session.send_custom_message(
            "pythonEditComponent", {"id": component.id, "properties": properties}
        )

    @render.ui
    def selected_visual_properties() -> ui.Tag:
        component = next(
            (item for item in document().components if str(item.id) == str(selected())), None
        )
        if component is None:
            return ui.p("Select a component on the canvas.")
        options = display_options(component)
        fields = visual_fields(component)
        if not options and not fields:
            return ui.p("No independently configurable visual fields for this component.")
        original = component.properties.get(
            "display",
            (
                ["label", "phase"]
                if component.type == "offset_line"
                else ["label"]
                if component.type == "termination"
                else ["label", "loss"]
            ),
        )
        if not isinstance(original, list) or any(not isinstance(v, str) for v in original):
            return ui.p(
                "Imported display array is invalid; source is retained unchanged.", role="alert"
            )
        controls: list[ui.Tag] = [
            ui.input_text("visual_component_id", "Visual form component ID", str(component.id))
        ]
        for field in fields:
            controls.append(
                ui.input_numeric(
                    f"visual_{field.key}",
                    field.label,
                    component.number(field.key, field.default),
                )
            )
        if component.type == "combiner":
            controls.append(
                ui.input_checkbox(
                    "visual_load_modulation",
                    "Load-modulation annotation (not a synthesis model)",
                    component.properties.get("load_modulation") is True,
                )
            )
        if options:
            controls.append(
                ui.input_checkbox_group(
                    "visual_display",
                    "Visible canvas annotations",
                    options,
                    selected=[v for v in original if isinstance(v, str) and v in options],
                )
            )
        return ui.div(
            *controls,
            ui.p(
                "Annotations do not change calculation models, instantiate matching networks "
                "or implement unequal splitting/load modulation. Some legacy annotations "
                "appear only for particular topology renderers. Termination resistance remains "
                "visible inside its symbol. Unknown imported display fields are retained."
            ),
            ui.input_action_button("apply_visual_properties", "Apply annotations / display"),
        )

    @reactive.effect
    @reactive.event(input.apply_visual_properties)
    async def _apply_visual() -> None:
        component = next(
            (item for item in document().components if str(item.id) == str(selected())), None
        )
        try:
            if component is None or str(component.id) != input.visual_component_id():
                raise ValueError("Selection changed; wait for the current visual form")
            values = {
                field.key: input[f"visual_{field.key}"]() for field in visual_fields(component)
            }
            if component.type == "combiner":
                values["load_modulation"] = input.visual_load_modulation()
            properties = validated_visual_properties(
                component,
                values,
                list(input.visual_display()) if display_options(component) else [],
            )
        except ValueError as exc:
            failure(f"Visual edit rejected: {exc}")
            return
        await session.send_custom_message(
            "pythonEditComponent", {"id": component.id, "properties": properties}
        )

    @render.ui
    def selected_design_properties() -> ui.Tag:
        component = next(
            (item for item in document().components if str(item.id) == str(selected())), None
        )
        if component is None:
            return ui.p("Select a component on the canvas.")
        extra = component.model_extra or {}
        controls = []
        for key, label in text_fields(component).items():
            value = component.properties.get(key, "phase" if key == "offset_role" else "")
            controls.append(
                ui.input_text(
                    f"design_{key}",
                    label,
                    "" if value is None else str(value),
                )
            )
        return ui.div(
            ui.input_text("design_component_id", "Design form component ID", str(component.id)),
            *controls,
            ui.input_numeric("design_x", "Canvas X (canvas units)", component.x),
            ui.input_numeric("design_y", "Canvas Y (canvas units)", component.y),
            ui.input_numeric("design_rotation", "Rotation (deg)", extra.get("rotation", 0)),
            ui.input_checkbox("design_flipH", "Flip horizontally", bool(extra.get("flipH", False))),
            ui.input_checkbox("design_flipV", "Flip vertically", bool(extra.get("flipV", False))),
            ui.p(
                "Metadata labels do not instantiate a foundry model "
                "or synthesize a matching network. "
                "Calculation inputs remain in the separate form above."
            ),
            ui.input_action_button("apply_design_properties", "Apply design metadata / geometry"),
        )

    @reactive.effect
    @reactive.event(input.apply_design_properties)
    async def _apply_design() -> None:
        component = next(
            (item for item in document().components if str(item.id) == str(selected())), None
        )
        try:
            if component is None or str(component.id) != input.design_component_id():
                raise ValueError("Selection changed; wait for the current design form")
            properties = validated_design_properties(
                component, {key: input[f"design_{key}"]() for key in text_fields(component)}
            )
            geometry = ComponentGeometry.model_validate(
                {key: input[f"design_{key}"]() for key in ("x", "y", "rotation", "flipH", "flipV")}
            )
        except ValueError as exc:
            failure(f"Design edit rejected: {exc}")
            return
        await session.send_custom_message(
            "pythonEditComponent",
            {
                "id": component.id,
                "properties": properties,
                "geometry": geometry.model_dump(),
            },
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

    @render.ui
    def workspace_download_control() -> ui.Tag:
        if workspace_export() is not None:
            return ui.download_button("download_workspace", "Download four-canvas workspace")
        return ui.p("Prepare a workspace download from the canvas toolbar.")

    @render.download(filename="rfview_workspace.json", media_type="application/json")
    def download_workspace() -> Iterator[str]:
        text = workspace_export()
        if text is None:
            raise ValueError("Prepare a fresh workspace snapshot first")
        yield text

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
