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
        second.close()

        malformed = Path(temp) / "invalid.json"
        malformed.write_text('{"components":[{"id":1,"type":"unknown"}]}', encoding="utf-8")
        page.locator("#load_document").set_input_files(malformed)
        expect(page.locator("#status")).to_contain_text("Load rejected")
        assert page.evaluate("window.paCanvas.components.length") == 4

        for width in (375, 768, 1440):
            if width == 375:
                page.get_by_text("Technology charts and summary", exact=True).click()
            page.set_viewport_size({"width": width, "height": 1000})
            expect(page.locator("#technology_charts svg").first).to_be_visible()
            assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth + 1"), (
                f"Page overflows at width {width}"
            )
        assert not errors, errors
        browser.close()
    print(
        "Browser smoke passed: calculation, charts, guardrails, edit, undo/redo, "
        "download/upload, isolation and errors."
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default="http://127.0.0.1:3840")
    parser.add_argument("--channel", help="Use an installed browser, e.g. msedge or chrome")
    args = parser.parse_args()
    main(args.url, args.channel)
