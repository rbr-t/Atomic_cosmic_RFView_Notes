# Crawl4AI KB Ingestion Pilot

This folder contains a guarded pilot pipeline for collecting public vendor product metadata into the RF PA knowledge base.

## Files
- `crawl_kb_pipeline.py`: crawl and build validation artifacts.
- `configs/vendor_seed_catalog.yaml`: allowlist, crawl policy, and seed product URLs.
- `requirements.txt`: Python dependencies.
- `outputs/`: generated pilot run artifacts.

## Safety Model
- Allowlist-only crawling.
- robots.txt checks enabled.
- Low default request rate.
- Provenance captured for every record.
- Validation and review gate before any KB update.

## Runtime Compatibility
- Recommended Python: 3.12 or 3.13.
- Python 3.14 is not suitable for this toolchain on this workstation because the Crawl4AI dependency chain fails on the `lxml` wheel/build path.
- A working local environment has now been verified with Python 3.13 and Playwright Chromium.

## Quick Start
1. Create a Python 3.13 virtual environment:
   - `py -3.13 -m venv .venv`
2. Install dependencies:
   - `.venv\Scripts\python.exe -m pip install -r requirements.txt`
3. Install the Playwright browser runtime:
   - `.venv\Scripts\python.exe -m playwright install chromium`
4. Run Ampleon pilot:
   - `.venv\Scripts\python.exe crawl_kb_pipeline.py --vendor ampleon --max-products 2`
5. Run NXP pilot:
   - `.venv\Scripts\python.exe crawl_kb_pipeline.py --vendor nxp --max-products 2`

## Validation
- Validate the seed catalog, latest pilot artifacts, and crawler-produced KB records:
   - `python validate_kb_pipeline.py`
- CI runs the same validator in:
   - `PA design App/.github/workflows/crawl4ai-kb-guard.yml`

Outputs are written to `outputs/`.
