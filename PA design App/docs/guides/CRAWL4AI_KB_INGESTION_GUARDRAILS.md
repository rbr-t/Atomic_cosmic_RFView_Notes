# Crawl4AI KB Ingestion Guardrails

## Purpose
This guide defines integrity, legal, and operational safeguards for using Crawl4AI to collect RF transistor product and datasheet metadata into the PA device knowledge base.

## Scope
- In scope: public product pages and datasheet links from approved vendor domains.
- Out of scope: authenticated portals, paywalled PDFs, or sources with no crawl permission.

## Legal and License Checklist
- Crawl4AI usage is under Apache-2.0 terms.
- Keep third-party notices and license text in repository documentation.
- Preserve upstream copyright and license notices when redistributing tooling.
- Verify vendor website terms of use before scaling crawl frequency.
- Use only public URLs and respect robots directives.

## Technical Guardrails (Must-Have)
- Domain allowlist: hard block any URL outside approved domains.
- Robots policy: set robots check on every crawl run.
- Rate limiting: delay per request and low concurrency by default.
- User agent transparency: include internal bot user-agent with contact marker.
- Provenance tracking: include URL, UTC crawl timestamp, HTTP status, and content hash.
- Validation gate: reject records missing required KB schema fields.
- Human review gate: run in artifact mode first; do not auto-merge by default.
- Duplicate protection: deduplicate by `device_id` when appending to vendor libraries.

## Pilot Configuration
- Ampleon discovery target:
  - https://www.ampleon.com/products/mobile-broadband/1.4-2.2-ghz-transistors/#/
- NXP discovery target:
  - https://www.nxp.com/products/product-selector:PRODUCT-SELECTOR?category=c250_c65&page=1
- Initial verification set:
  - 2 products for Ampleon
  - 2 products for NXP

## Runbook
1. Install Python dependencies:
   - `pip install -r "PA design App/tools/crawl4ai_kb_ingestion/requirements.txt"`
   - Use Python 3.12 or 3.13 for real Crawl4AI runs.
2. Generate pilot verification artifact for Ampleon:
   - `python "PA design App/tools/crawl4ai_kb_ingestion/crawl_kb_pipeline.py" --vendor ampleon --max-products 2`
3. Generate pilot verification artifact for NXP:
   - `python "PA design App/tools/crawl4ai_kb_ingestion/crawl_kb_pipeline.py" --vendor nxp --max-products 2`
4. Review outputs in:
   - `PA design App/tools/crawl4ai_kb_ingestion/outputs/`
5. Optional controlled merge (only after review):
   - `python "PA design App/tools/crawl4ai_kb_ingestion/crawl_kb_pipeline.py" --vendor nxp --max-products 2 --apply`
6. Run validation guard locally before commit:
   - `python "PA design App/tools/crawl4ai_kb_ingestion/validate_kb_pipeline.py"`

## Review Criteria Before Merge
- Required fields present: device_id, part_number, manufacturer, technology, freq_min_mhz, freq_max_mhz.
- Frequency range is valid (max >= min).
- Datasheet/product URL is reachable and on approved domain.
- Confidence is not `low` for production merge.
- Notes clearly indicate if values are inferred vs explicitly scraped.

## Operational Notes
- The pilot script is conservative by design; it emits review artifacts first.
- Parsed values from dynamic pages may be incomplete; unknown fields remain minimal until validated.
- This workflow avoids silent contamination of `data/kb/*/devices.json`.
- CI now validates the latest artifact per vendor plus crawler-produced KB provenance records before merge.
