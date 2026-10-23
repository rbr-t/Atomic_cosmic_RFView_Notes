"""Run against the preview: python tests/browser_smoke.py http://127.0.0.1:3840."""

import argparse
import json
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
        page.get_by_text("Touchstone magnitude and phase viewer", exact=True).click()
        fixture = Path(__file__).parent / "fixtures" / "touchstone"
        page.locator("#touchstone_upload").set_input_files(fixture / "reference_db.s2p")
        expect(page.locator("#touchstone_status")).to_contain_text("Loaded reference_db.s2p")
        expect(page.locator("#touchstone_view svg")).to_have_count(2)
        expect(page.locator("#touchstone_view svg").first).to_be_visible()
        page.locator("#touchstone_parameter").select_option("S21")
        expect(page.locator("#touchstone_view")).to_contain_text("S21 magnitude")
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
        page.locator("#touchstone_representation").select_option("Z")
        expect(page.locator("#touchstone_view")).to_contain_text("requires a two-port dataset")
        expect(page.locator("#touchstone_view svg")).to_have_count(0)
        page.locator("#touchstone_representation").select_option("S")
        expect(page.locator("#touchstone_view")).to_contain_text("S11 magnitude")
        expect(page.locator("#summary")).to_contain_text("35.400 dBm")
        page.get_by_text("Touchstone magnitude and phase viewer", exact=True).click()

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
        second.close()

        malformed = Path(temp) / "invalid.json"
        malformed.write_text('{"components":[{"id":1,"type":"unknown"}]}', encoding="utf-8")
        page.locator("#load_document").set_input_files(malformed)
        expect(page.locator("#status")).to_contain_text("Load rejected")
        assert page.evaluate("window.paCanvas.components.length") == 4

        for width in (375, 768, 1440):
            if width == 375:
                page.get_by_text("Technology charts and summary", exact=True).click()
                page.get_by_text("Full-stage transistor sizing", exact=True).click()
                page.get_by_text("Touchstone magnitude and phase viewer", exact=True).click()
            page.set_viewport_size({"width": width, "height": 1000})
            expect(page.locator("#technology_charts svg").first).to_be_visible()
            expect(page.locator("#full_stage_sizing table")).to_be_visible()
            expect(page.locator("#touchstone_view svg").first).to_be_visible()
            assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth + 1"), (
                f"Page overflows at width {width}"
            )
        assert not errors, errors
        browser.close()
    print(
        "Browser smoke passed: calculation, full-stage sizing, charts, guardrails, "
        "Touchstone viewer, edit, undo/redo, download/upload, isolation and errors."
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default="http://127.0.0.1:3840")
    parser.add_argument("--channel", help="Use an installed browser, e.g. msedge or chrome")
    args = parser.parse_args()
    main(args.url, args.channel)
