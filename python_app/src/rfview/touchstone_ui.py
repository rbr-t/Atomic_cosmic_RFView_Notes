from shiny import ui

from rfview.domain.touchstone import TouchstoneData
from rfview.technology_ui import Trace, line_chart

MAX_VIEWER_FREQUENCIES = 2000


def touchstone_panel(network: TouchstoneData, parameter: str) -> ui.Tag:
    if len(network.freq_ghz) > MAX_VIEWER_FREQUENCIES:
        raise ValueError(f"Viewer limit is {MAX_VIEWER_FREQUENCIES} frequency records")
    points = [point for point in network.points if point.param == parameter]
    if not points:
        raise ValueError(f"Parameter {parameter} is not present in {network.filename}")
    return ui.div(
        ui.p(
            f"Dataset: {network.filename} | Ports: {network.nports} | "
            f"Reference impedance: {network.z0:g} ohm | "
            f"Records: {len(network.freq_ghz)} | "
            f"Range: {network.freq_ghz[0]:g}-{network.freq_ghz[-1]:g} GHz | "
            f"Format: {network.data_format.upper()}"
        ),
        line_chart(
            f"{parameter} magnitude",
            "Frequency (GHz)",
            "Magnitude (dB)",
            [Trace(parameter, [(p.freq_ghz, p.mag_db) for p in points], "#ff7f11")],
        ),
        line_chart(
            f"{parameter} phase",
            "Frequency (GHz)",
            "Wrapped phase (deg)",
            [Trace(parameter, [(p.freq_ghz, p.phase_deg) for p in points], "#ff7f11")],
        ),
        ui.p(
            "Phase is wrapped, not unwrapped. Zero magnitude uses the legacy -300 dB floor. "
            "No passivity, calibration or measurement-integrity certification is performed."
        ),
    )
