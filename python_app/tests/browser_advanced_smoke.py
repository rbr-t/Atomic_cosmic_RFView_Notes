"""Advanced RF structures, geometry controls and confirmed workspace lifecycle."""

import argparse
import json
import tempfile
from pathlib import Path

from playwright.sync_api import Error, expect, sync_playwright

from rfview.domain.touchstone import parse_touchstone


def close_notifications(page) -> None:
    for _ in range(16):
        close_button = page.locator(".shiny-notification-close").first
        if close_button.count() == 0:
            return
        try:
            close_button.click(timeout=1500)
        except Error:
            continue


def main(url: str) -> None:
    errors: list[str] = []
    expect.set_options(timeout=15_000)
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
        close_notifications(page)
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
        expect(page.locator("#design_label")).not_to_have_value("Review DUT")
        page.locator("#python_redo").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c=>c.id===20).properties.label === 'Review DUT'"
        )
        expect(page.locator("#design_label")).to_have_value("Review DUT")
        page.locator("#design_x").fill("1000001")
        page.locator("#apply_design_properties").click()
        expect(page.locator("#status")).to_contain_text("Design edit rejected")
        close_notifications(page)
        assert page.evaluate("window.paCanvas.components.find(c=>c.id===20).x") == 450
        page.get_by_text("Design metadata and geometry", exact=True).click()

        page.locator("#python_canvas_slot").select_option("2")
        page.wait_for_function("window.paCanvas.components.length === 5")
        page.locator(".component-termination").click()
        page.get_by_text("Component annotations and display", exact=True).click()
        expect(page.locator("#visual_impedance")).to_have_value("50.0")
        page.locator("#visual_impedance").fill("75")
        page.locator("#visual_power_rating").fill("20")
        page.locator("#visual_display input[value='label']").uncheck()
        page.locator("#apply_visual_properties").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c=>c.type==='termination').properties.impedance === 75"
        )
        assert page.evaluate(
            "window.paCanvas.components.find(c=>c.type==='termination').properties.display"
        ) == ["impedance"]
        page.locator("#python_undo").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c=>c.type==='termination').properties.impedance === 50"
        )
        expect(page.locator("#visual_impedance")).to_have_value("50.0")
        page.locator("#python_redo").click()
        page.wait_for_function(
            "window.paCanvas.components.find(c=>c.type==='termination').properties.impedance === 75"
        )
        expect(page.locator("#visual_impedance")).to_have_value("75.0")
        page.locator("#visual_vswr").fill("0.5")
        page.locator("#apply_visual_properties").click()
        expect(page.locator("#status")).to_contain_text("VSWR must be at least one")
        assert (
            page.evaluate(
                "window.paCanvas.components.find(c=>c.type==='termination').properties.vswr"
            )
            == 1
        )
        close_notifications(page)
        page.get_by_text("Component annotations and display", exact=True).click()
        page.locator("#python_canvas_slot").select_option("1")
        page.wait_for_function("window.paCanvas.components.length === 4")

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
        page.locator("#touchstone_basis").select_option("single_ended")
        page.locator("#touchstone_representation").select_option("S")
        expect(page.locator("#touchstone_view")).to_contain_text("Analysis basis: single_ended")
        with page.expect_download() as download:
            page.locator("#download_transformed_network").click()
        transformed_file = Path(temp) / "single-ended.ts"
        download.value.save_as(transformed_file)
        transformed = parse_touchstone(
            transformed_file.read_text(encoding="utf-8"), "single-ended.ts"
        )
        assert transformed.mixed_mode_order == ()
        assert transformed.reference_ohms == (50, 50, 75)
        with page.expect_download() as download:
            page.locator("#download_touchstone").click()
        source_export = Path(temp) / "source-mixed.ts"
        download.value.save_as(source_export)
        assert parse_touchstone(
            source_export.read_text(encoding="utf-8"), "source.ts"
        ).mixed_mode_order
        page.locator("#touchstone_basis").select_option("mixed")
        page.locator("#touchstone_modes").fill("D1,2 S3 C1,2")
        expect(page.locator("#touchstone_view")).to_contain_text("not physical single-ended ports")
        page.locator("#touchstone_modes").fill("D1,3 C1,3 S2")
        expect(page.locator("#touchstone_view")).to_contain_text("equal single-ended")
        page.locator("#touchstone_basis").select_option("source")
        legacy_noise = Path(temp) / "legacy-noise.s2p"
        legacy_noise.write_text(
            "# GHz S RI R 75\n1 .1 0 2 0 .01 0 .2 0\n.5 1 .3 -45 .2\n",
            encoding="utf-8",
        )
        page.locator("#touchstone_upload").set_input_files(legacy_noise)
        expect(page.locator("#touchstone_status")).to_contain_text("Loaded legacy-noise.s2p")
        page.locator("#touchstone_representation").select_option("Noise")
        expect(page.locator("#noise_parameters_table tbody tr")).to_have_count(1)
        expect(page.locator("#noise_parameters_table")).to_contain_text("15")

        page.get_by_text("Load-pull measurements and contours", exact=True).click()
        page.locator("#loadpull_format").select_option("alps_mdf")
        source = next(
            (Path(__file__).resolve().parents[2] / "PA design App" / "data" / "sample-files").glob(
                "*1.800GHz.tdp.mdf"
            )
        )
        page.locator("#loadpull_upload").set_input_files(source)
        expect(page.locator("#loadpull_upload_progress")).to_contain_text(
            "Upload complete", timeout=60_000
        )
        page.locator("#loadpull_import").click()
        try:
            expect(page.locator("#loadpull_status")).to_contain_text(
                "214/97584 source rows", timeout=60_000
            )
        except AssertionError:
            print(
                "ALPS browser failure state:",
                page.evaluate(
                    """() => ({
                  socket: Shiny.shinyapp.$socket?.readyState,
                  adapter: Shiny.shinyapp.$inputValues.loadpull_format,
                  imported: Shiny.shinyapp.$inputValues.loadpull_import,
                  file: Shiny.shinyapp.$inputValues.loadpull_upload,
                  notifications: document.querySelector('#shiny-notification-panel')?.textContent
                })"""
                ),
                "page errors:",
                errors,
                flush=True,
            )
            raise
        expect(page.locator("#loadpull_alps_block option")).to_have_count(456)
        page.locator("#loadpull_alps_block").select_option("2")
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text("block 2/456", timeout=60_000)
        page.locator("#loadpull_alps_selection").select_option("backoff")
        page.locator("#loadpull_alps_plane").select_option("instrument")
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text(
            "456/97584 source rows", timeout=60_000
        )
        expect(page.locator("#loadpull_sweep option")).to_have_count(1)
        expect(page.locator("#loadpull_measurement_table tbody tr")).to_have_count(456)
        page.locator("#loadpull_show_contours").check()
        expect(page.locator(".loadpull-contour").first).to_be_visible()
        for width in (375, 768, 1440):
            page.set_viewport_size({"width": width, "height": 1000})
            expect(page.locator("#loadpull_view svg")).to_be_visible()
            assert page.evaluate("document.documentElement.scrollWidth <= innerWidth + 1")
        with page.expect_download() as download:
            page.locator("#download_loadpull").click()
        exported_alps = Path(temp) / "selected-alps.json"
        download.value.save_as(exported_alps)
        subset = json.loads(exported_alps.read_text(encoding="utf-8"))
        assert len(subset["points"]) == 456
        assert subset["points"][0]["extra"]["source.bo"] == 0
        assert subset["points"][0]["source_strings"]["fname"] == source.name.removesuffix(
            ".tdp.mdf"
        )
        assert "Instrument" in subset["metadata"]["gamma_plane"]
        page.locator("#loadpull_alps_backoff").fill("999")
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text(
            "No ALPS rows match", timeout=60_000
        )
        expect(page.locator("#loadpull_status")).to_contain_text("Last valid dataset retained")
        expect(page.locator("#loadpull_measurement_table tbody tr")).to_have_count(456)
        close_notifications(page)

        page.locator("#loadpull_show_contours").uncheck()
        page.locator("#loadpull_format").select_option("spl_plan")
        plan_source = next(source.parent.glob("*.spl"))
        page.locator("#loadpull_upload").set_input_files(plan_source)
        expect(page.locator("#loadpull_upload_progress")).to_contain_text("Upload complete")
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text("Section 1/8 at 1.75 GHz")
        expect(page.locator("#loadpull_status")).to_contain_text(
            "811 valid measurements, 260 VALID=0 slots excluded"
        )
        expect(page.locator("#loadpull_status")).to_contain_text("All 7791 source slots checked")
        expect(page.locator("#loadpull_spl_section option")).to_have_count(8)
        expect(page.locator("#loadpull_view")).to_contain_text("Eff_col is drain efficiency (%)")
        for width in (375, 768, 1440):
            page.set_viewport_size({"width": width, "height": 1000})
            expect(page.locator("#loadpull_spl_section")).to_be_visible()
            assert page.evaluate("document.documentElement.scrollWidth <= innerWidth + 1")
        with page.expect_download() as download:
            page.locator("#download_loadpull").click()
        exported_plan = Path(temp) / "selected-plan.json"
        download.value.save_as(exported_plan)
        plan_subset = json.loads(exported_plan.read_text(encoding="utf-8"))
        assert len(plan_subset["points"]) == 811
        first = plan_subset["points"][0]
        assert first["pout_dbm"] == 28.09750
        assert first["idc_a"] == 1.92811920
        assert first["vdc_v"] == 30.04331
        assert first["de_pct"] == 1.11396
        assert first["extra"]["source.iq_out_ma"] == 1802.29898
        assert first["extra"]["source.pdis"] == 57.28988
        assert first["extra"]["source.poutw"] == 0.64528
        page.locator("#loadpull_spl_section").select_option("2")
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text("Section 2/8 at 1.8 GHz")
        expect(page.locator("#loadpull_status")).to_contain_text("632 valid measurements")
        page.locator("#loadpull_fractional").check()
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text("SPL plan Eff_col uses percent")
        expect(page.locator("#loadpull_status")).to_contain_text("Last valid dataset retained")
        expect(page.locator("#loadpull_view")).to_contain_text("Selected section 2/8")
        close_notifications(page)
        page.locator("#loadpull_fractional").uncheck()
        invalid_plan = Path(temp) / "truncated-plan.spl"
        invalid_plan.write_text(
            plan_source.read_text(encoding="utf-8-sig").split("Freq = 2.0500 GHz")[0],
            encoding="utf-8",
        )
        page.locator("#loadpull_upload").set_input_files(invalid_plan)
        expect(page.locator("#loadpull_upload_progress")).to_contain_text("Upload complete")
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text("missing declared")
        expect(page.locator("#loadpull_status")).to_contain_text("Last valid dataset retained")
        expect(page.locator("#loadpull_view")).to_contain_text("Selected section 2/8")
        close_notifications(page)
        page.locator("#loadpull_format").select_option("cst")
        cst_source = next(source.parent.glob("*.cst"))
        page.locator("#loadpull_upload").set_input_files(cst_source)
        expect(page.locator("#loadpull_upload_progress")).to_contain_text("Upload complete")
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text("Block 1/365")
        expect(page.locator("#loadpull_status")).to_contain_text("23/8915 source rows")
        expect(page.locator("#loadpull_cst_block option")).to_have_count(365)
        expect(page.locator("#cst_wave_table tbody tr")).to_have_count(23)
        with page.expect_download() as download:
            page.locator("#download_loadpull").click()
        cst_export = Path(temp) / "cst-selected.json"
        download.value.save_as(cst_export)
        peak = json.loads(cst_export.read_text(encoding="utf-8"))
        page.locator("#loadpull_cst_normalization").select_option("rms_voltage")
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text("Wave normalization: rms_voltage")
        with page.expect_download() as download:
            page.locator("#download_loadpull").click()
        download.value.save_as(cst_export)
        rms = json.loads(cst_export.read_text(encoding="utf-8"))
        assert abs(rms["points"][0]["pin_w"] - 2 * peak["points"][0]["pin_w"]) < 1e-12
        assert rms["points"][0]["extra"]["source.z0load"] == 5
        page.locator("#loadpull_cst_block").select_option("365")
        page.locator("#loadpull_import").click()
        expect(page.locator("#loadpull_status")).to_contain_text("Block 365/365")
        page.get_by_text("Local device knowledge base", exact=True).click()
        page.locator("#kb_search").click()
        expect(page.locator("#kb_status")).to_contain_text("Found 22 matching record(s)")
        expect(page.locator(".kb-device-card")).to_have_count(22)
        expect(page.locator("#kb_device_detail")).to_contain_text("catalog_source_sha256")
        page.locator("#kb_manufacturer").select_option("NXP")
        page.locator("#kb_frequency_mhz").fill("500")
        page.locator("#kb_query").fill("MRF1K50H")
        page.locator("#kb_search").click()
        expect(page.locator("#kb_status")).to_contain_text("Found 1 matching record(s)")
        expect(page.locator(".kb-device-card")).to_have_count(1)
        expect(page.locator(".kb-device-card")).to_contain_text("MRF1K50H")
        expect(page.locator("#kb_device_detail")).to_contain_text("nxp/devices.json")
        expect(page.locator("#kb_device_detail")).to_contain_text("datasheet")
        for width in (375, 768, 1440):
            page.set_viewport_size({"width": width, "height": 1000})
            assert page.evaluate("document.documentElement.scrollWidth <= innerWidth + 1")
        close_notifications(page)
        assert not errors, errors
        browser.close()
    print(
        "Advanced browser smoke passed: comparison, lifecycle, geometry/history, "
        "triangles, v1/v2 noise, mixed-mode transforms, annotations, ALPS, SPL, CST, "
        "and local KB search."
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default="http://127.0.0.1:3840")
    main(parser.parse_args().url)
