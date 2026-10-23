"""Advanced RF structures, geometry controls and confirmed workspace lifecycle."""

import argparse
import tempfile
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

from rfview.domain.touchstone import parse_touchstone


def main(url: str) -> None:
    errors: list[str] = []
    with sync_playwright() as playwright, tempfile.TemporaryDirectory() as temp:
        browser = playwright.chromium.launch()
        page = browser.new_page(viewport={"width": 1440, "height": 1000})
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(url)
        page.wait_for_function("window.paCanvas?.components.length === 4")
        page.locator("#python_compare").click()
        expect(page.locator(".comparison-card")).to_have_count(4)
        expect(page.locator("#workspace_comparison_view")).to_contain_text("35.400 dBm")
        for width in (375, 768, 1440):
            page.set_viewport_size({"width": width, "height": 1000})
            expect(page.locator(".comparison-card svg").first).to_be_visible()
            assert page.evaluate("document.documentElement.scrollWidth <= innerWidth + 1")
        page.locator("#input_power_dbm").fill("10")
        expect(page.locator(".comparison-card")).to_have_count(0)
        page.locator("#input_power_dbm").fill("20")
        page.locator("#python_compare").click()
        expect(page.locator(".comparison-card")).to_have_count(4)

        # Replacement is explicit, cancellable and isolates the target's lifecycle.
        page.locator("#python_clear_canvas").click()
        expect(page.locator(".modal")).to_be_visible()
        page.get_by_role("button", name="Cancel", exact=True).click()
        assert page.evaluate("window.paCanvas.components.length") == 4
        page.locator("#python_copy_slot").select_option("2")
        page.locator("#python_copy_canvas").click()
        page.locator("#confirm_canvas_replace").click()
        expect(page.locator(".modal")).not_to_be_visible()
        page.locator("#python_canvas_slot").select_option("2")
        page.wait_for_function("window.paCanvas.components.length === 4")
        page.locator("#python_clear_canvas").click()
        page.locator("#confirm_canvas_replace").click()
        page.wait_for_function("window.paCanvas.components.length === 0")
        assert page.evaluate("window.paCanvas.history.length") == 1
        page.locator("#python_canvas_slot").select_option("1")
        page.wait_for_function("window.paCanvas.components.length === 4")
        page.locator("#python_clear_canvas").click()
        expect(page.locator(".modal")).to_be_visible()
        page.evaluate(
            "window.paCanvas.components[0].properties.label = 'Changed while confirming';"
            "window.paCanvas.saveHistory()"
        )
        page.locator("#confirm_canvas_replace").click()
        expect(page.locator("#status")).to_contain_text("Target canvas changed")
        assert page.evaluate("window.paCanvas.components.length") == 4
        page.locator(".shiny-notification-close").click()
        page.locator("#python_undo").click()

        page.locator("#python_canvas_slot").select_option("2")
        page.wait_for_function("window.paCanvas.components.length === 0")
        for kind in ("matching", "splitter", "combiner", "offset_line", "termination"):
            page.locator("#python_component_type").select_option(kind)
            page.locator("#python_add").click()
            page.wait_for_function(
                "(kind) => window.paCanvas.components.some(c => c.type === kind)",
                arg=kind,
            )
        assert page.evaluate("window.paCanvas.components.length") == 5
        page.locator("#python_component_type").select_option("transistor")
        page.locator("#python_canvas_slot").select_option("1")
        page.wait_for_function("window.paCanvas.components.length === 4")

        # Geometry/metadata edits must retain saved operating points and be undoable.
        page.locator('.component[data-id="20"] polygon').click(position={"x": 5, "y": 20})
        page.get_by_text("Design metadata and geometry", exact=True).click()
        expect(page.locator("#design_component_id")).to_have_value("20")
        original = page.evaluate(
            "JSON.parse(JSON.stringify(window.paCanvas.components.find(c=>c.id===20)))"
        )
        page.locator("#design_label").fill("Review DUT")
        page.locator("#design_x").fill("450")
        page.locator("#design_rotation").fill("90")
        page.locator("#apply_design_properties").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c=>c.id===20).properties.label === 'Review DUT'"
        )
        edited = page.evaluate("window.paCanvas.components.find(c=>c.id===20)")
        assert edited["x"] == 450 and edited["rotation"] == 90
        for key in (
            "gain",
            "pout_p3db",
            "pout_pavg",
            "pin_p3db",
            "pin_pavg",
            "pae_p3db",
            "pae_pavg",
        ):
            assert edited["properties"].get(key) == original["properties"].get(key)
        page.locator("#python_undo").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c=>c.id===20).properties.label !== 'Review DUT'"
        )
        page.locator("#python_redo").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c=>c.id===20).properties.label === 'Review DUT'"
        )
        page.locator("#design_x").fill("1000001")
        page.locator("#apply_design_properties").click()
        expect(page.locator("#status")).to_contain_text("Design edit rejected")
        page.locator(".shiny-notification-close").click()
        assert page.evaluate("window.paCanvas.components.find(c=>c.id===20).x") == 450
        page.get_by_text("Design metadata and geometry", exact=True).click()

        page.get_by_text("Touchstone magnitude and phase viewer", exact=True).click()
        noise = Path(temp) / "noise.ts"
        noise.write_text(
            "[Version] 2.0\n# MHz S RI R 50\n[Number of Ports] 2\n"
            "[Two-Port Data Order] 12_21\n[Number of Frequencies] 1\n"
            "[Number of Noise Frequencies] 2\n[Reference] 75 25\n[Matrix Format] Lower\n"
            "[Network Data]\n1000 0.1 -0.2 0.01 -0.03 0.2 -0.1\n"
            "[Noise Data]\n500 1.2 0.3 -45 19\n1500 2.3 0.4 30 22\n[End]\n",
            encoding="utf-8",
        )
        page.locator("#touchstone_upload").set_input_files(noise)
        expect(page.locator("#touchstone_status")).to_contain_text("Loaded noise.ts")
        page.locator("#touchstone_representation").select_option("Noise")
        expect(page.locator("#noise_parameters_table tbody tr")).to_have_count(2)
        expect(page.locator("#touchstone_view")).to_contain_text("option-line reference 50 ohm")
        for width in (375, 768, 1440):
            page.set_viewport_size({"width": width, "height": 1000})
            expect(page.locator("#noise_parameters_table")).to_be_visible()
            assert page.evaluate("document.documentElement.scrollWidth <= innerWidth + 1")
        with page.expect_download() as download:
            page.locator("#download_touchstone").click()
        exported = Path(temp) / "noise-export.s2p"
        download.value.save_as(exported)
        restored = parse_touchstone(exported.read_text(encoding="utf-8"), exported.name)
        assert len(restored.noise) == 2 and restored.noise_reference_ohm == 50
        points = {point.param: point for point in restored.points}
        assert points["S12"].imag == points["S21"].imag == -0.03

        mixed = Path(temp) / "mixed.ts"
        mixed.write_text(
            "[Version] 2.0\n# GHz S RI R 50\n[Number of Ports] 3\n"
            "[Number of Frequencies] 1\n[Reference] 50 50 75\n"
            "[Mixed-Mode Order] D1,2 S3 C1,2\n[Network Data]\n"
            "1 " + " ".join(["0.1 0"] * 9) + "\n[End]\n",
            encoding="utf-8",
        )
        page.locator("#touchstone_upload").set_input_files(mixed)
        expect(page.locator("#touchstone_status")).to_contain_text("Loaded mixed.ts")
        page.locator("#touchstone_parameter").select_option("S33")
        page.locator("#touchstone_representation").select_option("Smith")
        expect(page.locator("#touchstone_view")).to_contain_text("25 ohm")
        expect(page.locator("#touchstone_view")).to_contain_text("not physical single-ended ports")
        page.locator("#touchstone_representation").select_option("Stability")
        expect(page.locator("#touchstone_view")).to_contain_text("declared basis")
        assert not errors, errors
        browser.close()
    print(
        "Advanced browser smoke passed: comparison, lifecycle, geometry/history, "
        "triangles, noise and mixed-mode."
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default="http://127.0.0.1:3840")
    main(parser.parse_args().url)
