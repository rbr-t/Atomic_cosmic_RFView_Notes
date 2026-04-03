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

## Quick Start
1. Install dependencies:
   - `pip install -r requirements.txt`
2. Run Ampleon pilot:
   - `python crawl_kb_pipeline.py --vendor ampleon --max-products 2`
3. Run NXP pilot:
   - `python crawl_kb_pipeline.py --vendor nxp --max-products 2`

Outputs are written to `outputs/`.
