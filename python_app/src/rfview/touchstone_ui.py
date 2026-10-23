from shiny import ui

from rfview.domain.network_parameters import Matrix2, s_to_y, s_to_z
from rfview.domain.stability import stability_metrics
from rfview.domain.touchstone import TouchstoneData
from rfview.smith_ui import smith_chart
from rfview.technology_ui import Trace, line_chart

MAX_VIEWER_FREQUENCIES = 2000


def _two_port_matrix(network: TouchstoneData, offset: int) -> Matrix2:
    record = network.points[offset * 4 : offset * 4 + 4]
    values = {p.param: complex(p.real, p.imag) for p in record}
    return ((values["S11"], values["S12"]), (values["S21"], values["S22"]))


def _stability_table(network: TouchstoneData) -> ui.Tag:
    rows: list[ui.Tag] = []
    warnings: dict[str, None] = {}
    for offset, freq in enumerate(network.freq_ghz):
        try:
            metrics = stability_metrics(_two_port_matrix(network, offset))
        except ValueError as exc:
            raise ValueError(
                f"Stability calculation failed at {freq:g} GHz: {exc}. "
                "No partial table is displayed; select S to view the source data."
            ) from exc
        warnings.update(dict.fromkeys(metrics.warnings))
        values = [
            metrics.delta_mag,
            metrics.K,
            metrics.mu_in,
            metrics.mu_out,
            metrics.B1,
            metrics.msg_db,
            metrics.mag_db,
        ]
        rows.append(
            ui.tags.tr(
                ui.tags.th(f"{freq:.12g}", scope="row"),
                *(
                    ui.tags.td("Undefined" if value is None else f"{value:.12g}")
                    for value in values
                ),
                ui.tags.td("True" if metrics.stable else "False"),
            )
        )
    return ui.div(
        ui.h3("Two-port stability - legacy-r-stability-v1"),
        ui.p(
            "Uses the complete two-port network, independent of the S-parameter selector. "
            "All metrics except frequency and gain are dimensionless. "
            "Undefined K includes the legacy infinite-K case; no rows are dropped."
        ),
        ui.div(
            ui.h4("Model warnings"),
            ui.tags.ul(*(ui.tags.li(message) for message in warnings)),
            class_="migration-notice",
        ),
        ui.div(
            ui.tags.table(
                ui.tags.caption("Legacy stability and gain metrics at every uploaded frequency"),
                ui.tags.thead(
                    ui.tags.tr(
                        *(
                            ui.tags.th(label, scope="col")
                            for label in (
                                "Frequency (GHz)",
                                "|Delta|",
                                "K",
                                "mu_in",
                                "mu_out",
                                "B1",
                                "Legacy MSG (dB)",
                                "Legacy MAG (dB)",
                                "Legacy stable flag",
                            )
                        )
                    )
                ),
                ui.tags.tbody(*rows),
                id="stability_metrics_table",
            ),
            class_="table-scroll",
            tabindex="0",
            role="region",
            **{"aria-label": "Scrollable two-port stability metrics"},
        ),
    )


def touchstone_panel(network: TouchstoneData, parameter: str, representation: str = "S") -> ui.Tag:
    if len(network.freq_ghz) > MAX_VIEWER_FREQUENCIES:
        raise ValueError(f"Viewer limit is {MAX_VIEWER_FREQUENCIES} frequency records")
    points = [point for point in network.points if point.param == parameter]
    if not points:
        raise ValueError(f"Parameter {parameter} is not present in {network.filename}")
    if representation not in ("S", "Z", "Y", "Smith", "Stability"):
        raise ValueError(f"Unsupported network representation: {representation}")
    if representation in ("Z", "Y") and network.nports != 2:
        raise ValueError("Z/Y conversion requires a two-port dataset; select S for one-port data")
    if representation == "Stability" and network.nports != 2:
        raise ValueError(
            "Stability analysis requires a two-port dataset; select S for one-port data"
        )
    charts: list[ui.Tag]
    if representation == "Stability":
        charts = [_stability_table(network)]
    elif representation == "Smith":
        charts = [smith_chart(points, parameter, network.z0)]
    elif representation == "S":
        charts = [
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
        ]
    else:
        convert = s_to_z if representation == "Z" else s_to_y
        converted: list[tuple[float, complex]] = []
        row, col = int(parameter[1]) - 1, int(parameter[2]) - 1
        for offset, freq in enumerate(network.freq_ghz):
            matrix = _two_port_matrix(network, offset)
            try:
                result = convert(matrix, network.z0)
            except ValueError as exc:
                raise ValueError(
                    f"{representation} conversion failed at {freq:g} GHz: {exc}. "
                    "No partial curve is displayed; select S to view the source data."
                ) from exc
            converted.append((freq, result[row][col]))
        label = representation + parameter[1:]
        unit = "ohm" if representation == "Z" else "S"
        charts = [
            line_chart(
                f"{label} real",
                "Frequency (GHz)",
                f"Real ({unit})",
                [Trace(label, [(f, v.real) for f, v in converted], "#ff7f11")],
            ),
            line_chart(
                f"{label} imaginary",
                "Frequency (GHz)",
                f"Imaginary ({unit})",
                [Trace(label, [(f, v.imag) for f, v in converted], "#ff7f11")],
            ),
        ]
    return ui.div(
        ui.p(
            f"Dataset: {network.filename} | Ports: {network.nports} | "
            f"Reference impedance: {network.z0:g} ohm | "
            f"Records: {len(network.freq_ghz)} | "
            f"Range: {network.freq_ghz[0]:g}-{network.freq_ghz[-1]:g} GHz | "
            f"Format: {network.data_format.upper()}"
        ),
        *charts,
        ui.p(
            "Phase is wrapped, not unwrapped. Zero magnitude uses the legacy -300 dB floor. "
            "No passivity, calibration or measurement-integrity certification is performed."
        ),
        ui.p(
            "Z/Y views use a common real reference impedance and the legacy 1e-15 "
            "determinant threshold. Y is displayed in siemens (S); "
            "this unit is distinct from dimensionless scattering parameters."
        ),
    )
