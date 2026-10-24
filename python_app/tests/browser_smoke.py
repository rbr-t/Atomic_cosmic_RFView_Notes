"""Run against the preview: python tests/browser_smoke.py http://127.0.0.1:3840."""

import argparse
import csv
import json
import re
import tempfile
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


def main(url: str, channel: str | None = None) -> None:
    errors: list[str] = []
    with sync_playwright() as playwright, tempfile.TemporaryDirectory() as temp:
        browser = playwright.chromium.launch(channel=channel)
        context = browser.new_context(viewport={"width": 1440, "height": 1000})
        page = context.new_page()
        page.on("pageerror", lambda error: errors.append(error.stack or str(error)))
        page.goto(url)
        page.wait_for_function("window.paCanvas?.components.length === 4")
        expect(page.locator("html")).not_to_have_class("shiny-disconnected")
        page.locator("#python_calculate").click()
        expect(page.locator("#summary")).to_contain_text("35.400 dBm")
        expect(page.locator("#sizing")).to_contain_text("33.800 ohm")
        expect(page.locator("#sizing")).to_contain_text("4.000 mm")
        page.get_by_text("Generic lifetime hypothesis (corrected v2)", exact=True).click()
        expect(page.locator("#lifetime_view")).to_contain_text("arrhenius-lifetime-v2")
        expect(page.locator("#lifetime_view")).to_contain_text("MTTF: 1e+06 hours")
        page.locator("#lifetime_tj").fill("150")
        expect(page.locator("#lifetime_view")).not_to_contain_text("MTTF: 1e+06 hours")
        lifetime = re.search(
            r"MTTF: ([\d.e+-]+) hours", page.locator("#lifetime_view").inner_text()
        )
        assert lifetime is not None and 0 < float(lifetime[1]) < 1e6
        page.locator("#lifetime_tj").fill("-273.15")
        expect(page.locator("#lifetime_view")).to_contain_text("Lifetime hypothesis rejected")
        expect(page.locator("#lifetime_view svg")).to_have_count(0)
        page.locator("#lifetime_tj").fill("125")
        page.locator("#lifetime_voltage").fill("0")
        expect(page.locator("#lifetime_view")).to_contain_text("Lifetime hypothesis rejected")
        page.locator("#lifetime_voltage").fill("1")
        expect(page.locator("#lifetime_view")).to_contain_text("MTTF: 1e+06 hours")
        expect(page.locator("#lifetime_view svg")).to_have_count(1)
        expect(page.locator("#summary")).to_contain_text("35.400 dBm")
        page.get_by_text("Generic lifetime hypothesis (corrected v2)", exact=True).click()
        page.get_by_text("Touchstone magnitude and phase viewer", exact=True).click()
        fixture = Path(__file__).parent / "fixtures" / "touchstone"
        page.locator("#touchstone_upload").set_input_files(fixture / "reference_db.s2p")
        expect(page.locator("#touchstone_status")).to_contain_text("Loaded reference_db.s2p")
        expect(page.locator("#touchstone_view svg")).to_have_count(2)
        expect(page.locator("#touchstone_view svg").first).to_be_visible()
        page.locator("#touchstone_parameter").select_option("S21")
        expect(page.locator("#touchstone_view")).to_contain_text("S21 magnitude")
        for representation, label, unit in (
            ("h", "h21", "dimensionless"),
            ("ABCD", "C", "S"),
            ("T", "T21", "dimensionless"),
        ):
            page.locator("#touchstone_representation").select_option(representation)
            expect(page.locator("#touchstone_view")).to_contain_text(f"{label} real")
            expect(page.locator("#touchstone_view")).to_contain_text(f"Imaginary ({unit})")
        with page.expect_download() as converted_download:
            page.locator("#download_network_csv").click()
        converted_file = Path(temp) / "converted.csv"
        converted_download.value.save_as(converted_file)
        with converted_file.open(encoding="utf-8", newline="") as handle:
            converted_rows = list(csv.DictReader(handle))
        assert len(converted_rows) == 8
        assert {row["parameter"] for row in converted_rows} == {"T11", "T12", "T21", "T22"}
        assert {row["unit"] for row in converted_rows} == {"dimensionless"}
        with page.expect_download() as source_download:
            page.locator("#download_touchstone").click()
        exported = Path(temp) / "export.s2p"
        source_download.value.save_as(exported)
        assert "# GHz S RI R 50" in exported.read_text(encoding="utf-8")
        page.locator("#touchstone_representation").select_option("Circles")
        expect(page.locator("#touchstone_view .stability-circle")).to_have_count(2)
        page.locator("#touchstone_frequency").select_option(index=1)
        expect(page.locator("#touchstone_view")).to_contain_text("at 2 GHz")
        for width in (375, 768, 1440):
            page.set_viewport_size({"width": width, "height": 1000})
            expect(page.locator("#touchstone_view svg").first).to_be_visible()
            assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth + 1")
        page.locator("#touchstone_representation").select_option("Stability")
        expect(page.locator("#stability_metrics_table tbody tr")).to_have_count(2)
        expect(page.locator("#touchstone_view")).to_contain_text("not the conventional 10*log10")
        stability_text = page.locator("#stability_metrics_table").inner_text()
        page.locator("#touchstone_representation").select_option("PowerGain")
        expect(page.locator("#power_gain_table tbody tr")).to_have_count(2)
        expect(page.locator("#touchstone_view")).to_contain_text("conventional-power-gain-v2")
        page.locator("#touchstone_representation").select_option("Stability")
        expect(page.locator("#stability_metrics_table")).to_have_text(stability_text)
        page.locator("#touchstone_parameter").select_option("S12")
        expect(page.locator("#stability_metrics_table")).to_have_text(stability_text)
        for width in (375, 768, 1440):
            page.set_viewport_size({"width": width, "height": 1000})
            expect(page.locator("#stability_metrics_table")).to_be_visible()
            assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth + 1")
        page.locator("#touchstone_parameter").select_option("S21")
        page.locator("#touchstone_representation").select_option("S")
        page.locator("#touchstone_upload").set_input_files(exported)
        expect(page.locator("#touchstone_status")).to_contain_text("Loaded export.s2p")
        expect(page.locator("#touchstone_frequency option")).to_have_count(2)
        page.locator("#touchstone_upload").set_input_files(fixture / "reference_db.s2p")
        expect(page.locator("#touchstone_status")).to_contain_text("Loaded reference_db.s2p")
        page.locator("#touchstone_parameter").select_option("S21")
        page.locator("#touchstone_representation").select_option("Smith")
        expect(page.locator("#touchstone_view")).to_contain_text("requires S11 or S22")
        expect(page.locator("#touchstone_view svg")).to_have_count(0)
        page.locator("#touchstone_parameter").select_option("S22")
        expect(page.locator("#touchstone_view svg")).to_have_count(1)
        expect(page.locator("#touchstone_view")).to_contain_text("S22 impedance Smith chart")
        page.locator("#touchstone_parameter").select_option("S21")
        page.locator("#touchstone_representation").select_option("Z")
        expect(page.locator("#touchstone_view")).to_contain_text("Z21 real")
        expect(page.locator("#touchstone_view")).to_contain_text("Imaginary (ohm)")
        page.locator("#touchstone_representation").select_option("Y")
        expect(page.locator("#touchstone_view")).to_contain_text("Y21 real")
        singular = Path(temp) / "singular.s2p"
        singular.write_text(
            "# GHz S RI R 50\n1 0 0 0 0 0 0 0 0\n2 -1 0 0 0 0 0 0 0", encoding="utf-8"
        )
        page.locator("#touchstone_upload").set_input_files(singular)
        expect(page.locator("#touchstone_view")).to_contain_text("failed at 2 GHz")
        expect(page.locator("#touchstone_view svg")).to_have_count(0)
        page.locator("#touchstone_representation").select_option("S")
        expect(page.locator("#touchstone_view svg")).to_have_count(2)
        page.locator("#touchstone_upload").set_input_files(fixture / "reference_db.s2p")
        expect(page.locator("#touchstone_status")).to_contain_text("Loaded reference_db.s2p")
        rejected = Path(temp) / "invalid.s2p"
        rejected.write_text("1 BAD", encoding="utf-8")
        page.locator("#touchstone_upload").set_input_files(rejected)
        expect(page.locator("#touchstone_status")).to_contain_text("Last valid dataset retained")
        expect(page.locator("#touchstone_view")).to_contain_text("reference_db.s2p")
        page.locator("#touchstone_upload").set_input_files(fixture / "reference_ma.s1p")
        expect(page.locator("#touchstone_view")).to_contain_text("reference_ma.s1p")
        expect(page.locator("#touchstone_parameter option")).to_have_count(1)
        expect(page.locator("#touchstone_view")).to_contain_text("S11 magnitude")
        multiport = Path(temp) / "three_port.ts"
        multiport.write_text(
            "[Version] 2.0\n# GHz S RI R 50\n[Number of Ports] 3\n"
            "[Number of Frequencies] 1\n[Reference] 50 60 70\n[Matrix Format] Full\n"
            "[Network Data]\n1 " + " ".join(["0.1 0"] * 9) + "\n[End]\n",
            encoding="utf-8",
        )
        page.locator("#touchstone_upload").set_input_files(multiport)
        expect(page.locator("#touchstone_status")).to_contain_text("Loaded three_port.ts")
        expect(page.locator("#touchstone_parameter option")).to_have_count(9)
        page.locator("#touchstone_parameter").select_option("S33")
        expect(page.locator("#touchstone_view")).to_contain_text("S33 magnitude")
        page.locator("#touchstone_representation").select_option("Smith")
        expect(page.locator("#touchstone_view")).to_contain_text("S33 impedance Smith chart")
        expect(page.locator("#touchstone_view")).to_contain_text("70 ohm")
        with page.expect_download() as multiport_download:
            page.locator("#download_touchstone").click()
        multiport_export = Path(temp) / "three_port_export.s3p"
        multiport_download.value.save_as(multiport_export)
        assert "[Reference] 50 60 70" in multiport_export.read_text(encoding="utf-8")
        page.locator("#touchstone_upload").set_input_files(multiport_export)
        expect(page.locator("#touchstone_status")).to_contain_text("Loaded three_port_export.s3p")
        page.locator("#touchstone_representation").select_option("Z")
        expect(page.locator("#touchstone_view")).to_contain_text("requires a two-port dataset")
        expect(page.locator("#download_network_csv")).to_have_count(0)
        unequal_ports = Path(temp) / "unequal.s2p"
        unequal_ports.write_text(
            "[Version] 2.0\n# GHz S RI R 50\n[Number of Ports] 2\n"
            "[Number of Frequencies] 1\n[Reference] 50 75\n"
            "[Two-Port Data Order] 12_21\n[Network Data]\n"
            "1 0.1 0 0.01 0 2 0 0.2 0\n[End]\n",
            encoding="utf-8",
        )
        page.locator("#touchstone_upload").set_input_files(unequal_ports)
        expect(page.locator("#touchstone_status")).to_contain_text("Loaded unequal.s2p")
        expect(page.locator("#touchstone_view")).to_contain_text("not silently renormalized")
        expect(page.locator("#download_network_csv")).to_have_count(0)
        expect(page.locator("#download_touchstone")).to_be_visible()
        page.locator("#touchstone_representation").select_option("T")
        expect(page.locator("#download_network_csv")).to_be_visible()
        page.locator("#touchstone_representation").select_option("S")
        page.locator("#touchstone_upload").set_input_files(fixture / "reference_ma.s1p")
        expect(page.locator("#touchstone_view")).to_contain_text("reference_ma.s1p")
        expect(page.locator("#touchstone_parameter option")).to_have_count(1)
        page.locator("#touchstone_representation").select_option("Stability")
        expect(page.locator("#touchstone_view")).to_contain_text("requires a two-port dataset")
        expect(page.locator("#stability_metrics_table")).to_have_count(0)
        page.locator("#touchstone_representation").select_option("Smith")
        expect(page.locator("#touchstone_view .smith-point")).to_have_count(3)
        expect(page.locator("#touchstone_view svg")).to_be_visible()
        active = Path(temp) / "active.s1p"
        active.write_text("# GHz S RI R 50\n1 1.1 0", encoding="utf-8")
        page.locator("#touchstone_upload").set_input_files(active)
        expect(page.locator("#touchstone_view")).to_contain_text("cannot display")
        expect(page.locator("#touchstone_view svg")).to_have_count(0)
        page.locator("#touchstone_upload").set_input_files(fixture / "reference_ma.s1p")
        expect(page.locator("#touchstone_view .smith-point")).to_have_count(3)
        page.locator("#touchstone_representation").select_option("Z")
        expect(page.locator("#touchstone_view")).to_contain_text("requires a two-port dataset")
        expect(page.locator("#touchstone_view svg")).to_have_count(0)
        page.locator("#touchstone_representation").select_option("S")
        expect(page.locator("#touchstone_view")).to_contain_text("S11 magnitude")
        expect(page.locator("#summary")).to_contain_text("35.400 dBm")
        page.get_by_text("Touchstone magnitude and phase viewer", exact=True).click()

        page.get_by_text("Load-pull measurements and contours", exact=True).click()
        lp_fixture = Path(__file__).parent / "fixtures" / "loadpull"
        page.locator("#loadpull_format").select_option("amcad")
        page.locator("#loadpull_upload").set_input_files(lp_fixture / "contour.csv")
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text("Loaded contour.csv")
        expect(page.locator("#loadpull_view .loadpull-point")).to_have_count(4)
        page.locator("#loadpull_show_contours").check()
        expect(page.locator("#loadpull_view .loadpull-contour").first).to_be_visible()
        page.locator("#loadpull_metric").select_option("pae_pct")
        expect(page.locator("#loadpull_view")).to_contain_text("Power-added efficiency (%)")
        with page.expect_download() as lp_pending:
            page.locator("#download_loadpull").click()
        lp_export = Path(temp) / "normalized-loadpull.json"
        lp_pending.value.save_as(lp_export)
        lp_data = json.loads(lp_export.read_text(encoding="utf-8"))
        assert len(lp_data["points"]) == 4
        assert lp_data["points"][0]["pae_pct"] == 20
        assert lp_data["warnings"]
        for width in (375, 768, 1440):
            page.set_viewport_size({"width": width, "height": 1000})
            expect(page.locator("#loadpull_view svg")).to_be_visible()
            assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth + 1")
        page.locator("#loadpull_upload").set_input_files(rejected)
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text("Last valid dataset retained")
        expect(page.locator("#loadpull_view .loadpull-point")).to_have_count(4)
        page.locator("#loadpull_format").select_option("mdif")
        page.locator("#loadpull_show_contours").uncheck()
        page.locator("#loadpull_upload").set_input_files(lp_fixture / "reference.mdif")
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text("Loaded reference.mdif")
        expect(page.locator("#loadpull_sweep option")).to_have_count(2)
        page.locator("#loadpull_sweep").select_option("sweep-1")
        expect(page.locator("#loadpull_view")).to_contain_text("3.5 GHz")
        expect(page.locator("#loadpull_view .loadpull-point")).to_have_count(1)
        page.locator("#loadpull_show_contours").check()
        expect(page.locator("#loadpull_view")).to_contain_text("Contours require")
        page.locator("#loadpull_show_contours").uncheck()
        expect(page.locator("#loadpull_view .loadpull-point")).to_have_count(1)
        page.get_by_text("Load-pull measurements and contours", exact=True).click()

        page.get_by_text("Full-stage transistor sizing", exact=True).click()
        suite = page.locator("#full_stage_sizing")
        expect(suite).to_be_visible()
        expect(suite).to_contain_text("33.800 ohm")
        expect(suite).to_contain_text("4.000 mm")
        expect(suite).to_contain_text("533.333 mA")
        expect(suite).to_contain_text("67.600 ohm")
        page.locator("#suite_topology").select_option("single_ended")
        expect(suite).to_contain_text("Not applicable")
        expect(suite.locator("table")).not_to_contain_text("Combiner length")
        page.locator("#suite_topology").select_option("doherty_asymmetric_9dB")
        expect(suite).to_contain_text("101.400 ohm")
        page.locator("#suite_frequency").fill("0")
        page.locator("#suite_frequency").press("Tab")
        expect(suite).to_contain_text("Full-stage sizing rejected")
        expect(suite.locator("table")).to_have_count(0)
        page.locator("#suite_frequency").fill("3.5")
        page.locator("#suite_frequency").press("Tab")
        expect(suite.locator("table")).to_contain_text("Combiner length")
        page.locator("#suite_pout").fill("")
        page.locator("#suite_pout").press("Tab")
        expect(suite).to_contain_text("Full-stage sizing rejected")
        page.locator("#suite_pout").fill("40")
        page.locator("#suite_pout").press("Tab")
        expect(suite).to_contain_text("33.800 ohm")
        page.locator("#suite_vdd").fill("2")
        page.locator("#suite_vdd").press("Tab")
        expect(suite).to_contain_text("Full-stage sizing rejected")
        page.locator("#suite_vdd").fill("28")
        page.locator("#suite_vdd").press("Tab")
        expect(suite.locator("table")).to_contain_text("33.800 ohm")
        expect(page.locator("#summary")).to_contain_text("35.400 dBm")
        page.get_by_text("Full-stage transistor sizing", exact=True).click()

        page.get_by_text("Technology charts and summary", exact=True).click()
        expect(page.locator("#technology_charts svg")).to_have_count(3)
        expect(page.locator("#technology_charts svg").first).to_be_visible()
        expect(page.locator("#technology_summary_table tbody tr")).to_have_count(6)
        expect(page.locator("#technology_charts polyline")).to_have_count(24)
        page.locator("#chart_technology").select_option("GaN_SiC")
        page.locator("#chart_pa_class").select_option("Doherty")
        expect(page.locator("#technology_summary_table tbody tr")).to_have_count(1)
        expect(page.locator("#technology_charts polyline")).to_have_count(4)
        expect(page.locator("#technology_charts")).to_contain_text("PAE-backoff curves - Doherty")
        expect(page.locator("#summary")).to_contain_text("35.400 dBm")
        page.locator("#chart_technology").select_option("all")
        expect(page.locator("#technology_summary_table tbody tr")).to_have_count(6)
        page.get_by_text("Technology charts and summary", exact=True).click()

        page.locator('.component[data-id="10"]').click()
        expect(page.locator("#edit_loss")).to_have_value("0.3")
        page.locator("#edit_loss").fill("-1")
        page.locator("#edit_loss").press("Tab")
        page.locator("#apply_properties").click()
        expect(page.locator("#status")).to_contain_text("Property edit rejected")
        assert (
            page.evaluate("window.paCanvas.components.find(c => c.id === 10).properties.loss")
            == 0.3
        )
        page.locator("#edit_loss").fill("1")
        page.locator("#edit_loss").press("Tab")
        page.locator("#apply_properties").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c => c.id === 10).properties.loss === 1"
        )
        expect(page.locator("#summary")).to_contain_text("No current result")
        page.locator("#python_undo").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c => c.id === 10).properties.loss === 0.3"
        )
        page.locator("#python_calculate").click()
        expect(page.locator("#summary")).to_contain_text("35.400 dBm")

        # Exercise the real selection event and Python-to-browser edit.
        page.locator('.component[data-id="20"] polygon').click(position={"x": 5, "y": 20})
        page.get_by_text("Technology guardrail advisory", exact=True).click()
        expect(page.locator("#guardrail_advisory")).to_contain_text("Choose a technology")
        page.locator("#guardrail_technology").select_option("GaN_SiC")
        expect(page.locator("#guardrail_advisory")).to_contain_text("Status: OK")
        page.locator("#guardrail_frequency").fill("41")
        page.locator("#guardrail_frequency").press("Tab")
        expect(page.locator("#guardrail_advisory")).to_contain_text("Status: ERROR")
        expect(page.locator("#guardrail_advisory")).to_contain_text("outside")
        expect(page.locator("#summary")).to_contain_text("35.400 dBm")
        page.locator("#guardrail_frequency").fill("3.5")
        page.locator("#guardrail_frequency").press("Tab")
        expect(page.locator("#guardrail_advisory")).to_contain_text("Status: OK")
        page.locator("#edit_gain_p3db").fill("18")
        page.locator("#edit_gain_p3db").press("Tab")
        page.locator("#apply_properties").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c => c.id === 20).properties.gain_p3db === 18"
        )
        expect(page.locator("#summary")).to_contain_text("No current result")
        page.locator("#python_calculate").click()
        expect(page.locator("#summary")).not_to_contain_text("35.400 dBm")
        page.locator("#python_undo").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c => c.id === 20).properties.gain_p3db === 16"
        )
        page.locator("#python_redo").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c => c.id === 20).properties.gain_p3db === 18"
        )

        page.evaluate(
            "window.paCanvas.svg.call(window.paCanvas.zoom.transform, "
            "d3.zoomIdentity.translate(31,17).scale(1.2))"
        )
        page.locator("#python_canvas_slot").select_option(index=1)
        page.wait_for_function("window.paCanvas.components.length === 0")
        assert page.evaluate("d3.zoomTransform(window.paCanvas.svg.node()).k") == 1
        page.locator("#python_add").click()
        page.wait_for_function("window.paCanvas.components.length === 1")
        page.locator("#python_canvas_slot").select_option(index=0)
        page.wait_for_function("window.paCanvas.components.length === 4")
        assert page.evaluate("d3.zoomTransform(window.paCanvas.svg.node()).k") == 1.2
        page.locator("#python_undo").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c => c.id === 20).properties.gain_p3db === 16"
        )
        page.locator("#python_redo").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c => c.id === 20).properties.gain_p3db === 18"
        )
        page.locator("#python_workspace_snapshot").click()
        with page.expect_download() as workspace_download:
            page.locator("#download_workspace").click()
        workspace_path = Path(temp) / "workspace.json"
        workspace_download.value.save_as(workspace_path)
        workspace = json.loads(workspace_path.read_text(encoding="utf-8"))
        assert workspace["active"] == "1"
        assert len(workspace["canvases"]["1"]["components"]) == 4
        assert len(workspace["canvases"]["2"]["components"]) == 1
        page.locator("#example").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c => c.id === 20).properties.gain_p3db === 16"
        )
        page.locator("#load_workspace").set_input_files(workspace_path)
        page.wait_for_function(
            "window.paCanvas.components.find(c => c.id === 20).properties.gain_p3db === 18"
        )
        assert page.evaluate("d3.zoomTransform(window.paCanvas.svg.node()).k") == 1
        invalid_workspace = Path(temp) / "invalid-workspace.json"
        invalid_workspace.write_text('{"active":"5","canvases":{}}', encoding="utf-8")
        page.locator("#load_workspace").set_input_files(invalid_workspace)
        expect(page.locator("#status")).to_contain_text("Workspace load rejected")
        assert page.evaluate("window.paCanvas.components.length") == 4
        page.locator("#python_canvas_slot").select_option(index=1)
        page.wait_for_function("window.paCanvas.components.length === 1")
        page.wait_for_function(
            "window.paCanvas.historyIndex === 0 && window.paCanvas.history.length === 1"
        )
        page.locator("#python_undo").click()
        assert page.evaluate("window.paCanvas.components.length") == 1
        page.locator("#python_canvas_slot").select_option(index=0)
        page.wait_for_function("window.paCanvas.components.length === 4")

        # Actual download and upload, including non-sequential IDs and graph edges.
        page.locator("#input_power_dbm").fill("21")
        page.locator("#input_power_dbm").press("Tab")
        page.locator("#python_snapshot").click()
        with page.expect_download() as pending:
            page.locator("#download_document").click()
        downloaded = Path(temp) / "lineup.json"
        pending.value.save_as(downloaded)
        saved = json.loads(downloaded.read_text(encoding="utf-8"))
        assert [component["id"] for component in saved["components"]] == [10, 20, 30, 40]
        assert len(saved["connections"]) == 4
        assert saved["metadata"]["python_operating_point"]["input_power_dbm"] == 21
        page.locator("#example").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c => c.id === 20).properties.gain_p3db === 16"
        )
        page.locator("#load_document").set_input_files(downloaded)
        page.wait_for_function(
            "window.paCanvas.components.find(c => c.id === 20).properties.gain_p3db === 18"
        )
        expect(page.locator("#input_power_dbm")).to_have_value("21")
        assert page.evaluate("window.paCanvas.components.map(c => c.id)") == [10, 20, 30, 40]
        page.locator("#python_calculate").click()
        expect(page.locator("#summary")).to_contain_text("System results")

        # A second actual WebSocket session must receive independent initial state.
        second = context.new_page()
        second.goto(url)
        second.wait_for_function("window.paCanvas?.components.length === 4")
        assert (
            second.evaluate(
                "window.paCanvas.components.find(c => c.id === 20).properties.gain_p3db"
            )
            == 16
        )
        expect(second.locator("#input_power_dbm")).to_have_value("20")
        expect(second.locator("#suite_topology")).to_have_value("doherty_symmetric")
        expect(second.locator("#touchstone_status")).to_contain_text("No Touchstone dataset")
        expect(second.locator("#touchstone_representation")).to_have_value("S")
        expect(second.locator("#loadpull_status")).to_contain_text("No load-pull dataset")
        second.locator("#python_canvas_slot").select_option(index=1)
        second.wait_for_function("window.paCanvas.components.length === 0")
        expect(second.locator("#cad_download_control")).to_contain_text(
            "Import a valid RF-CAD document"
        )
        second.close()

        malformed = Path(temp) / "invalid.json"
        malformed.write_text('{"components":[{"id":1,"type":"unknown"}]}', encoding="utf-8")
        page.locator("#load_document").set_input_files(malformed)
        expect(page.locator("#status")).to_contain_text("Load rejected")
        assert page.evaluate("window.paCanvas.components.length") == 4

        # Standalone RF-CAD documents import/export independently from the PA canvas.
        page.get_by_text("Standalone RF-CAD JSON import / export", exact=True).click()
        cad_source = Path(temp) / "legacy-cad.json"
        cad_payload = {
            "version": "1.0",
            "substrate": {"h": 0.508, "er": 3.55, "tanD": 0.0027, "t": 0.035},
            "components": [
                {
                    "id": "cmp_7",
                    "type": "microstrip",
                    "name": "Feed",
                    "x": 12,
                    "y": 4,
                    "rotation": 90,
                    "layer": "metal_top",
                    "params": {"W": 0.5, "L": 5, "vendor_param": "keep"},
                }
            ],
            "vendor_document_field": {"retain": True},
        }
        cad_source.write_text(json.dumps(cad_payload), encoding="utf-8")
        page.locator("#cad_upload").set_input_files(cad_source)
        expect(page.locator("#cad_status")).to_contain_text("1 component(s)")
        expect(page.locator("#cad_summary")).to_contain_text("Relative permittivity")
        expect(page.locator("#cad_summary")).to_contain_text("microstrip components")
        expect(page.locator("#cad_preview .cad-layout-component")).to_have_count(1)
        expect(page.locator("#cad_preview .cad-layout-svg")).to_have_attribute(
            "aria-label", "RF-CAD component positions in millimetres"
        )
        marker = page.locator("#cad_preview .cad-layout-component").first
        expect(marker).to_have_attribute("role", "img")
        expect(marker).to_have_attribute("tabindex", "0")
        expect(marker).to_have_attribute(
            "aria-label",
            "Feed; microstrip; x=12 mm, y=4 mm, rotation=90 degrees",
        )
        expect(marker.locator("title")).to_contain_text("x=12 mm, y=4 mm")
        marker.focus()
        expect(marker).to_be_focused()
        with page.expect_download() as cad_download:
            page.locator("#download_cad").click()
        cad_export_path = Path(temp) / "normalized-cad.json"
        cad_download.value.save_as(cad_export_path)
        cad_exported = json.loads(cad_export_path.read_text(encoding="utf-8"))
        assert cad_exported["vendor_document_field"] == {"retain": True}
        assert cad_exported["components"][0]["params"]["vendor_param"] == "keep"
        assert cad_exported["components"][0]["id"] == "cmp_7"
        invalid_cad = Path(temp) / "invalid-cad.json"
        invalid_cad.write_text('{"components":[{"id":"x","type":"bad"}]}', encoding="utf-8")
        page.locator("#cad_upload").set_input_files(invalid_cad)
        expect(page.locator("#cad_status")).to_contain_text("RF-CAD import rejected")
        expect(page.locator("#cad_preview .cad-layout-component")).to_have_count(1)
        with page.expect_download() as retained_cad_download:
            page.locator("#download_cad").click()
        retained_cad_download.value.save_as(Path(temp) / "retained-cad.json")
        assert (
            json.loads((Path(temp) / "retained-cad.json").read_text(encoding="utf-8"))
            == cad_exported
        )
        many_cad = Path(temp) / "many-components.json"
        many_cad.write_text(
            json.dumps(
                {
                    "version": "1.0",
                    "components": [
                        {
                            "id": f"cmp_{index}",
                            "type": "microstrip",
                            "x": index * 0.1,
                            "y": 0,
                            "rotation": 0,
                            "params": {"W": 0.5, "L": 5},
                        }
                        for index in range(251)
                    ],
                }
            ),
            encoding="utf-8",
        )
        page.locator("#cad_upload").set_input_files(many_cad)
        expect(page.locator("#cad_status")).to_contain_text("251 component(s)")
        expect(page.locator("#cad_preview .cad-layout-component")).to_have_count(250)
        expect(page.locator("#cad_preview")).to_contain_text("first 250 of 251")
        with page.expect_download() as bounded_preview_export:
            page.locator("#download_cad").click()
        bounded_export_path = Path(temp) / "all-components.json"
        bounded_preview_export.value.save_as(bounded_export_path)
        assert len(json.loads(bounded_export_path.read_text(encoding="utf-8"))["components"]) == 251

        for width in (375, 768, 1440):
            if width == 375:
                page.get_by_text("Technology charts and summary", exact=True).click()
                page.get_by_text("Full-stage transistor sizing", exact=True).click()
                page.get_by_text("Touchstone magnitude and phase viewer", exact=True).click()
                page.locator("#touchstone_representation").select_option("Smith")
            page.set_viewport_size({"width": width, "height": 1000})
            expect(page.locator("#technology_charts svg").first).to_be_visible()
            expect(page.locator("#full_stage_sizing table")).to_be_visible()
            expect(page.locator("#touchstone_view svg").first).to_be_visible()
            expect(page.locator("#touchstone_view .smith-point")).to_have_count(3)
            expect(page.locator("#cad_preview .cad-layout-svg")).to_be_visible()
            assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth + 1"), (
                f"Page overflows at width {width}"
            )
        assert not errors, errors
        browser.close()
    print(
        "Browser smoke passed: calculation, full-stage sizing, charts, guardrails, "
        "corrected lifetime/gain, multiport Touchstone/source/converted export, "
        "load-pull import/contours/export, canvas/workspace editing, undo/redo, "
        "download/upload, isolation and responsive error recovery."
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default="http://127.0.0.1:3840")
    parser.add_argument("--channel", help="Use an installed browser, e.g. msedge or chrome")
    args = parser.parse_args()
    main(args.url, args.channel)
