import math
import re

from rfview.domain.models import (
    Component,
    LineupDocument,
    LineupResult,
    PhaseResult,
    StageResult,
    finite,
    nonnegative,
    positive,
)
from rfview.domain.power import dbm_to_watts, sum_dbm


def _transistor(
    component: Component, stage: StageResult, architecture: str, warnings: list[str]
) -> None:
    gain = component.number("gain", 15)
    gain_full = component.number("gain_p3db", gain - 2)
    gain_bo = component.number("gain_bo", (gain + gain_full) / 2)
    p1db = component.number("p1db", 43)
    vdd = positive(component.number("vdd", 28), "Vdd (V)")
    rth = nonnegative(component.number("rth", 2.5), "thermal resistance (C/W)")
    pae = component.number("pae", 50) / 100
    dual_keys = ("pout_p3db", "pout_pavg", "pin_p3db", "pin_pavg")
    has_dual = all(component.properties.get(key) is not None for key in dual_keys)
    if has_dual:
        for key in dual_keys:
            component.number(key, 0)
        stage.pout_dbm = component.number("pout_p3db", 0)
        stage.pout_bo_dbm = component.number("pout_pavg", 0)
        pae = component.number("pae_p3db", pae * 100) / 100
        pae_bo = component.number("pae_pavg", pae * 70) / 100
    else:
        stage.pout_dbm = stage.pin_dbm + gain_full
        stage.pout_bo_dbm = stage.pin_bo_dbm + gain_bo
        ratio = 10 ** ((stage.pout_bo_dbm - stage.pout_dbm) / 10)
        doherty = (
            architecture.lower() == "doherty"
            or "doherty" in component.text("topology").lower()
            or re.search("main|peak|aux", component.text("pa_group").lower()) is not None
            or re.search("main|peak|aux", component.text("label").lower()) is not None
        )
        if doherty:
            pae_bo = (
                pae
                if stage.pout_dbm - stage.pout_bo_dbm <= 6
                else min(pae * math.sqrt(ratio / 10 ** (-6 / 10)), pae)
            )
        else:
            pae_bo = max(pae * ratio**0.8, 0.05)
    if not 0 < pae <= 1 or not 0 < pae_bo <= 1:
        raise ValueError(f"{stage.stage}: full and backoff efficiencies must be in (0, 100] %")
    stage.compressed = stage.pout_dbm > p1db
    stage.compressed_bo = stage.pout_bo_dbm > p1db
    if stage.compressed:
        warnings.append(f"{stage.stage}: Compressed by {stage.pout_dbm - p1db:.1f} dB")
        stage.pout_dbm = p1db
    if stage.compressed_bo:
        warnings.append(f"{stage.stage}: Compressed at backoff")
        stage.pout_bo_dbm = p1db
    pout_w = dbm_to_watts(stage.pout_dbm)
    pout_bo_w = dbm_to_watts(stage.pout_bo_dbm)
    stage.gain_db = gain
    stage.gain_full_db = stage.pout_dbm - stage.pin_dbm
    stage.gain_bo_db = stage.pout_bo_dbm - stage.pin_bo_dbm
    stage.pae_pct = pae * 100
    stage.pae_bo_pct = pae_bo * 100
    stage.pdc_w = pout_w / max(pae, 0.01)
    stage.pdc_bo_w = pout_bo_w / max(pae_bo, 0.01)
    stage.pdiss_w = stage.pdc_w - pout_w
    stage.pdiss_bo_w = stage.pdc_bo_w - pout_bo_w
    stage.idc_a = stage.pdc_w / vdd
    stage.tj_c = 25 + stage.pdiss_w * rth
    stage.tj_bo_c = 25 + stage.pdiss_bo_w * rth
    stage.de_pct = pout_w / stage.pdc_w * 100
    stage.de_bo_pct = pout_bo_w / stage.pdc_bo_w * 100
    stage.technology = component.text("technology", "GaN")
    if stage.tj_c > 150:
        warnings.append(f"{stage.stage}: High junction temp {stage.tj_c:.0f} C")


def calculate_lineup(
    document: LineupDocument,
    input_power_dbm: float = 0,
    backoff_db: float = 6,
    architecture: str = "conventional",
    *,
    use_canvas_operating_points: bool = True,
) -> LineupResult:
    """Reproduce the legacy cascade; keep its engineering assumptions explicit."""
    if not document.components:
        raise ValueError("No components in lineup")
    dbm_to_watts(input_power_dbm)
    nonnegative(backoff_db, "backoff (dB)")
    ordered = document.ordered_components()
    predecessors, successors = document.graph()
    outputs: dict[str, StageResult] = {}
    stages: list[StageResult] = []
    phases: list[PhaseResult] = []
    warnings: list[str] = []
    total_gain = total_pdc = total_pdc_bo = cumulative_phase = 0.0
    linear_pin, linear_bo = input_power_dbm, input_power_dbm - backoff_db
    if not document.connections and len(ordered) > 1:
        warnings.append("No connections: using legacy left-to-right serial cascade.")
    if use_canvas_operating_points and any(
        component.properties.get("pout_p3db") is not None for component in ordered
    ):
        warnings.append(
            "Using saved browser operating points where complete; "
            "these may override changed system input/backoff."
        )
    for index, original in enumerate(ordered, 1):
        component = original.model_copy(deep=True)
        if not use_canvas_operating_points:
            for key in ("pout_p3db", "pout_pavg", "pin_p3db", "pin_pavg", "pae_p3db", "pae_pavg"):
                component.properties.pop(key, None)
        key = str(component.id)
        preds = predecessors[key]
        if document.connections:
            if preds:
                if len(preds) > 1 and component.type != "combiner":
                    raise ValueError(f"Component {key}: multiple inputs require a combiner")
                full = [outputs[pred].pout_dbm for pred in preds]
                bo = [outputs[pred].pout_bo_dbm for pred in preds]
                pin = sum_dbm(full) if len(full) > 1 else full[0]
                pin_bo = sum_dbm(bo) if len(bo) > 1 else bo[0]
            else:
                pin, pin_bo = input_power_dbm, input_power_dbm - backoff_db
            if len(successors[key]) > 1 and component.type != "splitter":
                raise ValueError(f"Component {key}: multiple outputs require a splitter")
        else:
            pin, pin_bo = linear_pin, linear_bo
        stage = StageResult(
            id=key,
            stage=component.text("label", f"Stage_{index}"),
            type=component.type,
            pin_dbm=pin,
            pin_bo_dbm=pin_bo,
            pout_dbm=pin,
            pout_bo_dbm=pin_bo,
            gain_full_db=0,
            gain_bo_db=0,
        )
        if component.type == "transistor":
            _transistor(component, stage, architecture, warnings)
            total_gain += component.number("gain_p3db", component.number("gain", 15) - 2)
            total_pdc += stage.pdc_w or 0
            total_pdc_bo += stage.pdc_bo_w or 0
        elif component.type != "termination":
            default_loss = {"matching": 0.5, "offset_line": 0.2}.get(component.type, 0.3)
            loss = nonnegative(component.number("loss", default_loss), "insertion loss (dB)")
            stage.loss_db = loss
            effective_loss = loss
            if component.type == "splitter":
                stage.n_outputs = max(len(successors[key]), 1) if document.connections else 2
                stage.split_loss_db = 10 * math.log10(stage.n_outputs)
                stage.split_ratio = component.number("split_ratio", 0)
                if stage.split_ratio != 0:
                    raise ValueError("Unequal split_ratio is not supported by the legacy model")
                effective_loss += stage.split_loss_db
            elif component.type == "combiner":
                stage.n_inputs = len(preds) if document.connections else 2
                if stage.n_inputs == 0:
                    raise ValueError("A connected combiner requires an input")
                total_gain += 10 * math.log10(stage.n_inputs)
            elif component.type == "offset_line":
                stage.stage = component.text("label", "\u03bb/4 Line")
                stage.phase_shift_deg = component.number("phase_shift_deg", 90)
                stage.impedance = positive(component.number("impedance", 50), "impedance (ohm)")
                stage.offset_role = component.text("offset_role", "phase")
            stage.pout_dbm = pin - effective_loss
            stage.pout_bo_dbm = pin_bo - effective_loss
            stage.gain_full_db = stage.gain_bo_db = -effective_loss
            total_gain -= effective_loss
        phase = stage.phase_shift_deg or 0
        cumulative_phase += phase
        phases.append(
            PhaseResult(
                stage=stage.stage,
                type=stage.type,
                phase_contrib=phase,
                cumulative_phase=cumulative_phase,
            )
        )
        outputs[key] = stage
        if component.type != "termination":
            stages.append(stage)
            linear_pin, linear_bo = stage.pout_dbm, stage.pout_bo_dbm
    terminals = [outputs[str(comp.id)] for comp in ordered if not successors[str(comp.id)]]
    if document.connections:
        final = sum_dbm(stage.pout_dbm for stage in terminals)
        final_bo = sum_dbm(stage.pout_bo_dbm for stage in terminals)
        sources = [comp for comp in ordered if not predecessors[str(comp.id)]]
        if len(sources) > 1 or len(terminals) > 1:
            warnings.append(
                "Multiple sources/terminals: legacy model sums terminal powers but "
                "uses one system input for PAE. Interpret aggregate efficiencies with caution."
            )
    else:
        final, final_bo = linear_pin, linear_bo
    pout_w, pout_bo_w = dbm_to_watts(final), dbm_to_watts(final_bo)
    warnings.append(
        "Legacy model: matched ports, PDC = Pout / entered efficiency, P1dB output clipping, "
        "and traversal-summed phase/gain. This is not an EM or nonlinear device simulation."
    )
    rationale = "\n".join(
        [
            "PA LINEUP - legacy-r-v1",
            f"Input: {input_power_dbm:.2f} dBm; backoff: {backoff_db:.2f} dB",
            "Full power / backoff:",
            *(
                f"{s.stage}: {s.pin_dbm:.2f} -> {s.pout_dbm:.2f} dBm / "
                f"{s.pin_bo_dbm:.2f} -> {s.pout_bo_dbm:.2f} dBm"
                for s in outputs.values()
            ),
            *warnings,
        ]
    )
    result = LineupResult(
        backoff_db=backoff_db,
        input_power_dbm=input_power_dbm,
        final_pout_dbm=final,
        final_pout_w=pout_w,
        total_gain=total_gain,
        net_gain_db=final - input_power_dbm,
        total_pdc=total_pdc,
        system_pae=(pout_w - dbm_to_watts(input_power_dbm)) / total_pdc * 100 if total_pdc else 0,
        system_de=pout_w / total_pdc * 100 if total_pdc else 0,
        total_pdiss=total_pdc - pout_w,
        final_pout_bo_dbm=final_bo,
        final_pout_bo_w=pout_bo_w,
        total_pdc_bo=total_pdc_bo,
        system_pae_bo=(pout_bo_w - dbm_to_watts(input_power_dbm - backoff_db)) / total_pdc_bo * 100
        if total_pdc_bo
        else 0,
        system_de_bo=pout_bo_w / total_pdc_bo * 100 if total_pdc_bo else 0,
        total_pdiss_bo=total_pdc_bo - pout_bo_w,
        stage_results=stages,
        phase_results=phases,
        warnings=warnings,
        rationale=rationale,
    )
    for name, value in result.model_dump().items():
        if isinstance(value, float):
            finite(value, name)
    return result
