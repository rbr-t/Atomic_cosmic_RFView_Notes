"""Run against an isolated RFVIEW_PROJECT_DB preview, then rerun with --reopen."""

import argparse
import json
from pathlib import Path

from playwright.sync_api import Page, expect, sync_playwright

from rfview.project_store import ProjectStore


def close_errors(page: Page) -> None:
    page.evaluate(
        """() => document.querySelectorAll('.shiny-notification-close')
            .forEach(button => button.click())"""
    )


def open_project(page: Page, revision: int = 0) -> None:
    page.locator("#project_refresh").click()
    page.wait_for_function("document.querySelector('#project_choice').options.length === 1")
    page.locator("#project_choice").select_option(index=0)
    page.locator("#project_revision").fill(str(revision))
    page.locator("#python_open_project").click()
    expect(page.locator(".modal-title")).to_contain_text("Confirm project recovery")
    page.locator("#python_confirm_project_load").click()


def main(url: str, database: Path, reopen: bool) -> None:
    if not reopen and database.exists():
        raise ValueError("Use a new isolated preview database, not existing user projects")
    store = ProjectStore(database)
    errors: list[str] = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        page = browser.new_page(viewport={"width": 1440, "height": 1000})
        page.set_default_timeout(15000)
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(url)
        page.wait_for_function("window.paCanvas?.components.length === 4")
        details = page.get_by_text("Open or recover local project", exact=True)
        details.click()
        if reopen:
            open_project(page)
            expect(page.locator("#project_status")).to_contain_text("head revision 3")
            expect(page.locator("#project_status")).to_contain_text("snapshot 3")
            expect(page.locator("#input_power_dbm")).to_have_value("23")
            expect(page.locator("#python_canvas_slot")).to_have_value("2")
            page.wait_for_function("window.paCanvas.components.length === 1")
            open_project(page, 1)
            expect(page.locator("#project_status")).to_contain_text("head revision 3")
            expect(page.locator("#project_status")).to_contain_text("snapshot 1")
            expect(page.locator("#input_power_dbm")).to_have_value("21")
            page.wait_for_function("window.paCanvas.components.length === 4")
            page.locator("#python_canvas_slot").select_option("2")
            page.wait_for_function("window.paCanvas.components.length === 0")
            page.locator("#python_save_project").click()
            expect(page.locator("#project_status")).to_contain_text("head revision 4")
            project = store.list_projects()[0]
            assert store.load(project.id, 2).snapshot.operating_point.input_power_dbm == 23
            assert store.load(project.id, 4).snapshot.operating_point.input_power_dbm == 21
            assert store.load(project.id, 1).snapshot.workspace.active == "1"
        else:
            # No initialization, list, or save is performed implicitly on startup.
            assert not database.exists()
            page.locator("#python_save_project").click()
            expect(page.locator("#status")).to_contain_text("Open a local project")
            close_errors(page)
            page.locator("#project_name").fill("Browser project acceptance " + "x" * 80)
            page.locator("#input_power_dbm").fill("21")
            page.locator("#backoff_db").fill("8")
            page.locator("#architecture").select_option("conventional")
            page.locator("#use_canvas_operating_points").check()
            page.locator("#python_create_project").click()
            expect(page.locator("#project_status")).to_contain_text("head revision 1")
            first = store.list_projects()[0]
            saved = store.load(first.id)
            assert saved.snapshot.workspace.active == "1"
            assert len(saved.snapshot.workspace.canvases["1"].components) == 4
            assert not saved.snapshot.workspace.canvases["2"].components
            assert saved.snapshot.operating_point.input_power_dbm == 21
            assert saved.snapshot.operating_point.backoff_db == 8
            assert saved.snapshot.operating_point.architecture == "conventional"
            assert saved.snapshot.operating_point.use_canvas_operating_points
            page.locator("#python_canvas_slot").select_option("2")
            page.wait_for_function("window.paCanvas.components.length === 0")
            page.locator("#python_add").click()
            page.wait_for_function("window.paCanvas.components.length === 1")
            page.locator("#input_power_dbm").fill("23")
            page.locator("#python_save_project").click()
            expect(page.locator("#project_status")).to_contain_text("head revision 2")
            assert store.load(first.id).snapshot.workspace.active == "2"
            assert len(store.load(first.id).snapshot.workspace.canvases["2"].components) == 1

            # A second connection advances the head; this browser cannot silently overwrite it.
            other = store.save(first.id, 2, store.load(first.id).snapshot)
            page.locator("#python_save_project").click()
            expect(page.locator("#status")).to_contain_text("another session")
            expect(page.locator("#project_status")).to_contain_text("head revision 2")
            assert store.load(first.id) == other
            close_errors(page)

            # Recovery requires confirmation and rejects edits made while the dialog is open.
            page.locator("#project_refresh").click()
            page.wait_for_function("document.querySelector('#project_choice').options.length === 1")
            page.locator("#project_choice").select_option(index=0)
            page.locator("#project_revision").fill("1")
            page.locator("#python_open_project").click()
            expect(page.locator(".modal-title")).to_contain_text("Confirm project recovery")
            page.evaluate("Shiny.setInputValue('input_power_dbm', 24, {priority:'event'})")
            page.locator("#python_confirm_project_load").click()
            expect(page.locator("#status")).to_contain_text("Workspace changed")
            page.wait_for_function("window.paCanvas.components.length === 1")
            close_errors(page)

            assert store.load(first.id).info.revision == 3
            print(json.dumps({"restart_head": 3, "project_id": first.id}))
        for width in (375, 768, 1440):
            page.set_viewport_size({"width": width, "height": 1000})
            assert page.evaluate(
                "document.documentElement.scrollWidth <= window.innerWidth + 1"
            )
        assert not errors, errors
        browser.close()
    print(f"Project browser {'restart/recovery' if reopen else 'save/conflict'} checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--reopen", action="store_true")
    args = parser.parse_args()
    main(args.url, args.database, args.reopen)
