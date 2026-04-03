#!/usr/bin/env python3
"""Guarded Crawl4AI pilot pipeline for RF device KB ingestion.

This script is intentionally conservative:
- Crawls only approved domains from a seed catalog.
- Respects robots.txt when supported by Crawl4AI runtime config.
- Generates review artifacts first; does not modify KB unless --apply is set.
- Stores provenance and crawl status for every extracted record.
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import yaml

try:
    from crawl4ai import AsyncWebCrawler, BrowserConfig, CacheMode, CrawlerRunConfig  # type: ignore[import-not-found]

    HAS_CRAWL4AI = True
except Exception:
    HAS_CRAWL4AI = False


REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CONFIG_PATH = Path(__file__).resolve().parent / "configs" / "vendor_seed_catalog.yaml"
DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent / "outputs"
KB_ROOT = REPO_ROOT / "data" / "kb"


@dataclass
class CrawlPolicy:
    max_concurrency: int
    delay_seconds: float
    respect_robots_txt: bool
    user_agent: str
    allowed_domains: list[str]


@dataclass
class ProductSeed:
    part_number: str
    product_url: str
    expected: dict[str, Any]


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_catalog(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def domain_allowed(url: str, allowed_domains: list[str]) -> bool:
    host = urlparse(url).netloc.lower()
    return any(host == domain or host.endswith(f".{domain}") for domain in allowed_domains)


def content_sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="ignore")).hexdigest()


def infer_frequency_bounds(text: str) -> tuple[float | None, float | None]:
    # Matches patterns like "1.4 - 2.2 GHz" or "1800 to 2200 MHz"
    ghz_match = re.search(r"(\d+(?:\.\d+)?)\s*(?:-|to)\s*(\d+(?:\.\d+)?)\s*ghz", text, flags=re.IGNORECASE)
    if ghz_match:
        return float(ghz_match.group(1)) * 1000.0, float(ghz_match.group(2)) * 1000.0

    mhz_match = re.search(r"(\d+(?:\.\d+)?)\s*(?:-|to)\s*(\d+(?:\.\d+)?)\s*mhz", text, flags=re.IGNORECASE)
    if mhz_match:
        return float(mhz_match.group(1)), float(mhz_match.group(2))

    return None, None


def extract_title(text: str) -> str | None:
    line = next((ln.strip() for ln in text.splitlines() if ln.strip()), None)
    if not line:
        return None
    return line[:140]


async def crawl_urls(urls: list[str], policy: CrawlPolicy) -> dict[str, dict[str, Any]]:
    results: dict[str, dict[str, Any]] = {}

    if not HAS_CRAWL4AI:
        for url in urls:
            results[url] = {
                "success": False,
                "error": "crawl4ai_not_installed",
                "status_code": None,
                "markdown": "",
                "html": "",
                "metadata": {},
            }
        return results

    browser_cfg = BrowserConfig(headless=True, user_agent=policy.user_agent)
    run_cfg = CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        check_robots_txt=policy.respect_robots_txt,
        delay_before_return_html=policy.delay_seconds,
    )

    async with AsyncWebCrawler(config=browser_cfg) as crawler:
        for url in urls:
            try:
                result = await crawler.arun(url=url, config=run_cfg)
                results[url] = {
                    "success": bool(getattr(result, "success", False)),
                    "error": getattr(result, "error_message", None),
                    "status_code": getattr(result, "status_code", None),
                    "markdown": getattr(result, "markdown", "") or "",
                    "html": getattr(result, "html", "") or "",
                    "metadata": getattr(result, "metadata", {}) or {},
                }
            except Exception as exc:
                results[url] = {
                    "success": False,
                    "error": str(exc),
                    "status_code": None,
                    "markdown": "",
                    "html": "",
                    "metadata": {},
                }
    return results


def build_record(vendor: str, seed: ProductSeed, crawl_result: dict[str, Any]) -> dict[str, Any]:
    expected = seed.expected or {}
    manufacturer = expected.get("manufacturer", vendor.capitalize())
    technology = expected.get("technology", "Other")

    crawl_text = crawl_result.get("markdown") or crawl_result.get("html") or ""
    fmin_guess, fmax_guess = infer_frequency_bounds(crawl_text)

    freq_min = expected.get("freq_min_mhz", fmin_guess if fmin_guess is not None else 0.0)
    freq_max = expected.get("freq_max_mhz", fmax_guess if fmax_guess is not None else 0.0)

    confidence = "high" if crawl_result.get("success") and fmin_guess is not None else "medium"
    if not crawl_result.get("success"):
        confidence = "low"

    record = {
        "device_id": f"{vendor}_{seed.part_number}",
        "part_number": seed.part_number,
        "manufacturer": manufacturer,
        "family": expected.get("family"),
        "series": expected.get("series"),
        "technology": technology,
        "freq_min_mhz": float(freq_min),
        "freq_max_mhz": float(freq_max),
        "datasheet_url": seed.product_url,
        "knowledge_source": "datasheet",
        "knowledge_confidence": confidence,
        "status": "active",
        "tags": ["crawl4ai-pilot", vendor, technology.lower()],
        "notes": "Auto-seeded by Crawl4AI pilot. Requires engineering review before production merge.",
        "ingestion_provenance": {
            "crawled_at_utc": now_iso(),
            "crawl_success": crawl_result.get("success"),
            "http_status": crawl_result.get("status_code"),
            "source_domain": urlparse(seed.product_url).netloc,
            "source_title_hint": extract_title(crawl_result.get("markdown", "") or crawl_result.get("html", "")),
            "content_sha256": content_sha256(crawl_text),
            "crawl_error": crawl_result.get("error"),
        },
    }
    return record


def validate_minimum(record: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    required = ["device_id", "part_number", "manufacturer", "technology", "freq_min_mhz", "freq_max_mhz"]
    for field in required:
        if field not in record or record[field] in (None, ""):
            errors.append(f"missing_required:{field}")

    if record.get("freq_max_mhz", 0) < record.get("freq_min_mhz", 0):
        errors.append("invalid_frequency_range")

    if float(record.get("freq_max_mhz", 0)) <= 0:
        errors.append("missing_frequency_bounds")

    if record.get("knowledge_confidence") == "low":
        errors.append("low_confidence_requires_review")

    provenance = record.get("ingestion_provenance", {})
    if not provenance.get("crawl_success"):
        errors.append("crawl_failed_or_unavailable")

    return errors


def append_records_to_vendor_file(vendor: str, records: list[dict[str, Any]]) -> Path:
    vendor_file = KB_ROOT / vendor / "devices.json"
    if not vendor_file.exists():
        vendor_file.parent.mkdir(parents=True, exist_ok=True)
        vendor_file.write_text("[]\n", encoding="utf-8")

    existing = json.loads(vendor_file.read_text(encoding="utf-8"))
    if not isinstance(existing, list):
        raise ValueError(f"Expected JSON array in {vendor_file}")

    existing_ids = {item.get("device_id") for item in existing if isinstance(item, dict)}
    merged = existing + [r for r in records if r.get("device_id") not in existing_ids]

    vendor_file.write_text(json.dumps(merged, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    return vendor_file


async def run(args: argparse.Namespace) -> int:
    cfg = load_catalog(Path(args.config))

    policy_raw = cfg.get("crawl_policy", {})
    policy = CrawlPolicy(
        max_concurrency=int(policy_raw.get("max_concurrency", 2)),
        delay_seconds=float(policy_raw.get("delay_seconds", 1.5)),
        respect_robots_txt=bool(policy_raw.get("respect_robots_txt", True)),
        user_agent=str(policy_raw.get("user_agent", "RFView-KBIngestionBot/0.1")),
        allowed_domains=list(policy_raw.get("allowed_domains", [])),
    )

    vendors = cfg.get("vendors", {})
    if args.vendor not in vendors:
        raise ValueError(f"Vendor '{args.vendor}' not found in config.")

    vendor_cfg = vendors[args.vendor]
    seeds = [
        ProductSeed(
            part_number=item["part_number"],
            product_url=item["product_url"],
            expected=item.get("expected", {}),
        )
        for item in vendor_cfg.get("products", [])
    ]

    if args.max_products:
        seeds = seeds[: args.max_products]

    for seed in seeds:
        if not domain_allowed(seed.product_url, policy.allowed_domains):
            raise ValueError(f"Blocked URL outside allowlist: {seed.product_url}")

    crawled = await crawl_urls([seed.product_url for seed in seeds], policy)

    records: list[dict[str, Any]] = []
    validation: dict[str, list[str]] = {}
    for seed in seeds:
        rec = build_record(args.vendor, seed, crawled[seed.product_url])
        errs = validate_minimum(rec)
        records.append(rec)
        validation[rec["device_id"]] = errs

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    out_file = output_dir / f"{args.vendor}_pilot_run_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"

    bad = {k: v for k, v in validation.items() if v}

    payload = {
        "run_context": {
            "vendor": args.vendor,
            "started_at_utc": now_iso(),
            "crawl4ai_available": HAS_CRAWL4AI,
            "discovery_url": vendor_cfg.get("discovery_url"),
            "max_products": len(seeds),
            "policy": {
                "respect_robots_txt": policy.respect_robots_txt,
                "delay_seconds": policy.delay_seconds,
                "allowed_domains": policy.allowed_domains,
            },
        },
        "records": records,
        "validation": validation,
        "blocked_for_auto_merge": bool(bad),
    }

    out_file.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(f"[INFO] Wrote verification artifact: {out_file}")

    if args.apply:
        if bad:
            print("[WARN] Apply blocked due to validation errors.")
            return 2

        merged_file = append_records_to_vendor_file(args.vendor, records)
        print(f"[INFO] Updated vendor library: {merged_file}")

    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Crawl4AI guarded KB ingestion pilot.")
    parser.add_argument("--vendor", required=True, choices=["ampleon", "nxp"])
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument("--max-products", type=int, default=2)
    parser.add_argument("--apply", action="store_true", help="Append validated records to data/kb/<vendor>/devices.json")
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(run(parse_args())))
