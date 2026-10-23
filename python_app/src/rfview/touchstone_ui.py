from shiny import ui

from rfview.domain.network_parameters import Matrix2
from rfview.domain.stability import power_gain_estimates, stability_circles, stability_metrics
from rfview.domain.touchstone import TouchstoneData, converted_parameters
from rfview.smith_ui import smith_chart, stability_circle_chart
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


def _power_gain_table(network: TouchstoneData) -> ui.Tag:
    rows: list[ui.Tag] = []
    warnings: dict[str, None] = {}
    for offset, freq in enumerate(network.freq_ghz):
        try:
            result = power_gain_estimates(_two_port_matrix(network, offset))
        except ValueError as exc:
            raise ValueError(f"Power-gain calculation failed at {freq:g} GHz: {exc}") from exc
        warnings.update(dict.fromkeys(result.warnings))
        rows.append(
            ui.tags.tr(
                ui.tags.th(f"{freq:.12g}", scope="row"),
                *(
                    ui.tags.td("Undefined" if value is None else f"{value:.12g}")
                    for value in (result.msg_db, result.mag_db)
                ),
            )
        )
    return ui.div(
        ui.h3("Conventional power gain - conventional-power-gain-v2"),
        ui.tags.ul(*(ui.tags.li(message) for message in warnings)),
        ui.div(
            ui.tags.table(
                ui.tags.caption("Conventional power gain at every uploaded frequency"),
                ui.tags.thead(
                    ui.tags.tr(
                        *(
                            ui.tags.th(label, scope="col")
                            for label in (
                                "Frequency (GHz)",
                                "MSG expression (dB)",
                                "MAG (dB)",
                            )
                        )
                    )
                ),
                ui.tags.tbody(*rows),
                id="power_gain_table",
            ),
            class_="table-scroll",
            tabindex="0",
            role="region",
            **{"aria-label": "Scrollable conventional power gain"},
        ),
    )


def touchstone_panel(
    network: TouchstoneData, parameter: str, representation: str = "S", frequency_index: int = 0
) -> ui.Tag:
    if max(len(network.freq_ghz), len(network.noise)) > MAX_VIEWER_FREQUENCIES:
        raise ValueError(f"Viewer limit is {MAX_VIEWER_FREQUENCIES} frequency records")
    points = [point for point in network.points if point.param == parameter]
    if not points:
        raise ValueError(f"Parameter {parameter} is not present in {network.filename}")
    if representation not in (
        "S",
        "Z",
        "Y",
        "h",
        "ABCD",
        "T",
        "Smith",
        "Stability",
        "Circles",
        "PowerGain",
        "Noise",
    ):
        raise ValueError(f"Unsupported network representation: {representation}")
    if representation in ("Z", "Y", "h", "ABCD", "T") and network.nports != 2:
        raise ValueError(
            "Parameter conversion requires a two-port dataset; select S for one-port data"
        )
    references = network.port_references()
    if network.mixed_mode_order and representation not in ("S", "Smith", "Noise"):
        raise ValueError(
            "Mixed-mode data is preserved in its declared basis; "
            "single-ended conversion/stability analysis is not applied"
        )
    if representation in ("Stability", "Circles", "PowerGain") and network.nports != 2:
        raise ValueError(
            "Stability analysis requires a two-port dataset; select S for one-port data"
        )
    charts: list[ui.Tag]
    if representation == "Noise":
        if not network.noise:
            raise ValueError("No explicit Touchstone 2.0 noise data is present")
        rows = [
            ui.tags.tr(
                *(
                    ui.tags.td(f"{value:.12g}")
                    for value in (
                        point.freq_ghz,
                        point.minimum_nf_db,
                        point.gamma_opt_mag,
                        point.gamma_opt_deg,
                        point.resistance_ohm,
                    )
                )
            )
            for point in network.noise
        ]
        charts = [
            ui.p(
                f"Noise Gamma uses option-line reference {network.noise_reference_ohm:g} ohm, "
                "not per-port/modal references. Rn is in ohms (Touchstone 2.0). "
                "Frequencies are independent of the network grid; no interpolation, "
                "physical-limit repair or noise-circle prediction is performed."
            ),
            line_chart(
                "Minimum noise figure",
                "Frequency (GHz)",
                "Minimum NF (dB)",
                [
                    Trace(
                        "Minimum NF",
                        [(p.freq_ghz, p.minimum_nf_db) for p in network.noise],
                        "#ff7f11",
                    )
                ],
            ),
            ui.div(
                ui.tags.table(
                    ui.tags.caption("Source noise parameters (as measured)"),
                    ui.tags.thead(
                        ui.tags.tr(
                            *(
                                ui.tags.th(label, scope="col")
                                for label in (
                                    "Frequency (GHz)",
                                    "Minimum NF (dB)",
                                    "|Gamma_opt|",
                                    "Gamma_opt phase (deg)",
                                    "Rn (ohm)",
                                )
                            )
                        )
                    ),
                    ui.tags.tbody(*rows),
                    id="noise_parameters_table",
                ),
                class_="table-scroll",
                tabindex="0",
                role="region",
                **{"aria-label": "Scrollable noise parameters"},
            ),
        ]
    elif representation == "PowerGain":
        charts = [_power_gain_table(network)]
    elif representation == "Circles":
        if isinstance(frequency_index, bool) or not 0 <= frequency_index < len(network.freq_ghz):
            raise ValueError("Choose an available circle frequency")
        freq = network.freq_ghz[frequency_index]
        try:
            circles = stability_circles(_two_port_matrix(network, frequency_index))
            charts = [
                ui.h3(circles.model_version),
                ui.p(
                    "Uses the complete two-port network, independent of the S-parameter selector."
                ),
                ui.tags.ul(*(ui.tags.li(message) for message in circles.warnings)),
                stability_circle_chart(circles.load, "Load", freq),
                stability_circle_chart(circles.source, "Source", freq),
            ]
        except ValueError as exc:
            raise ValueError(f"Stability circles failed at {freq:g} GHz: {exc}") from exc
    elif representation == "Stability":
        charts = [_stability_table(network)]
    elif representation == "Smith":
        charts = [smith_chart(points, parameter, references[int(parameter[1]) - 1])]
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
        row, col = int(parameter[1]) - 1, int(parameter[2]) - 1
        label = (
            "ABCD"[row * 2 + col] if representation == "ABCD" else representation + parameter[1:]
        )
        selected = [
            point
            for point in converted_parameters(network, representation)
            if point.parameter == label
        ]
        unit = selected[0].unit
        converted = [(point.freq_ghz, point.value) for point in selected]
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
        *(
            [
                ui.p(
                    "Declared mixed-mode matrix order: "
                    + " | ".join(network.mixed_mode_order)
                    + ". Sij indices refer to these matrix modes, not physical single-ended ports. "
                    "Modal references below use 2R for differential and R/2 for common mode."
                )
            ]
            if network.mixed_mode_order
            else []
        ),
        ui.p(
            f"Dataset: {network.filename} | Ports: {network.nports} | "
            + (
                f"Reference impedance: {network.z0:g} ohm | "
                if len(set(references)) == 1
                else "Per-port reference impedances (ohm): "
                + ", ".join(f"{v:g}" for v in references)
                + " | "
            )
            + f"Records: {len(network.freq_ghz)} | "
            f"Range: {network.freq_ghz[0]:g}-{network.freq_ghz[-1]:g} GHz | "
            f"Format: {network.data_format.upper()} | Touchstone version: {network.version}"
        ),
        *charts,
        ui.p(
            "Phase is wrapped, not unwrapped. Zero magnitude uses the legacy -300 dB floor. "
            "No passivity, calibration or measurement-integrity certification is performed."
        ),
        ui.p(
            "Conversions use the legacy 1e-15 singularity threshold. Z/Y/h/ABCD use a "
            "common real reference impedance. ABCD: [V1,I1] = ABCD [V2,-I2]. "
            "Scattering transfer T: [b1,a1] = T [a2,b2]; it is not ABCD. "
            "Siemens (S) is distinct from dimensionless scattering parameters."
        ),
    )
