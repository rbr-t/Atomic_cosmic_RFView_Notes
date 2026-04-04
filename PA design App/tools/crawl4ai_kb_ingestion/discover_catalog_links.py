#!/usr/bin/env python3
"""Discover individual product page URLs from a vendor catalog page.

Crawls a catalog/listing URL and extracts links that match the vendor's
allowed domain, optionally filtered by a URL pattern.

Output: JSON file written to --output-dir with a list of discovered products.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urljoin, urlparse

import yaml

# Force UTF-8 output for Windows hosts
os.environ.setdefault("PYTHONUTF8", "1")
os.environ.setdefault("PYTHONIOENCODING", "utf-8")
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
if hasattr(sys.stderr, "reconfigure"):
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

try:
    from crawl4ai import AsyncWebCrawler, BrowserConfig, CacheMode, CrawlerRunConfig  # type: ignore[import-not-found]
    HAS_CRAWL4AI = True
except Exception:
    HAS_CRAWL4AI = False

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG_PATH = Path(__file__).resolve().parent / "configs" / "vendor_seed_catalog.yaml"
DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent / "outputs"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_catalog(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def domain_allowed(url: str, allowed_domains: list[str]) -> bool:
    host = urlparse(url).netloc.lower()
    return any(host == d or host.endswith(f".{d}") for d in allowed_domains)


def extract_links_from_content(content: str, base_url: str, allowed_domains: list[str],
                                url_pattern: str | None = None) -> list[str]:
    """Extract absolute URLs from markdown/HTML content that are within allowed domains."""
    links: set[str] = set()

    # Markdown links: [text](url)
    for m in re.finditer(r'\[([^\]]*)\]\((https?://[^)\s]+)\)', content):
        links.add(m.group(2).split("?")[0])  # strip query params for dedup

    # href="url" attributes
    for m in re.finditer(r'href=["\']([^"\']+)["\']', content, re.IGNORECASE):
        url = m.group(1)
        if not url.startswith("http"):
            url = urljoin(base_url, url)
        links.add(url.split("?")[0])

    # Filter: allowed domains only
    links = {u for u in links if domain_allowed(u, allowed_domains)}

    # Filter: URL pattern if specified
    if url_pattern:
        try:
            links = {u for u in links if re.search(url_pattern, u, re.IGNORECASE)}
        except re.error:
            pass

    # Exclude the catalog URL itself
    links.discard(base_url.split("?")[0])

    return sorted(links)


def infer_part_number_from_url(url: str) -> str:
    """Attempt to infer a part number from the last path segment."""
    path = urlparse(url).path.rstrip("/")
    return path.split("/")[-1] if path else "unknown"


async def discover(catalog_url: str, allowed_domains: list[str], user_agent: str,
                   delay_seconds: float, url_pattern: str | None,
                   max_links: int) -> dict:
    """Crawl catalog_url and return list of discovered product links."""
    if not HAS_CRAWL4AI:
        return {
            "success": False,
            "error": "crawl4ai_not_installed",
            "catalog_url": catalog_url,
            "links": [],
        }

    browser_cfg = BrowserConfig(headless=True, user_agent=user_agent)
    run_cfg = CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        delay_before_return_html=delay_seconds,
    )

    async with AsyncWebCrawler(config=browser_cfg) as crawler:
        try:
            result = await crawler.arun(url=catalog_url, config=run_cfg)
            success = bool(getattr(result, "success", False))
            markdown = getattr(result, "markdown", "") or ""
            html = getattr(result, "html", "") or ""
            content = markdown if markdown else html
        except Exception as exc:
            return {
                "success": False,
                "error": str(exc),
                "catalog_url": catalog_url,
                "links": [],
            }

    links = extract_links_from_content(content, catalog_url, allowed_domains, url_pattern)

    if max_links > 0:
        links = links[:max_links]

    products = [
        {
            "part_number": infer_part_number_from_url(u),
            "product_url": u,
            "source": "catalog_discovery",
        }
        for u in links
    ]

    return {
        "success": success,
        "catalog_url": catalog_url,
        "discovered_at_utc": now_iso(),
        "url_pattern": url_pattern,
        "total_found": len(products),
        "products": products,
    }


async def run(args: argparse.Namespace) -> int:
    cfg = load_catalog(Path(args.config))
    policy_raw = cfg.get("crawl_policy", {})
    allowed_domains: list[str] = list(policy_raw.get("allowed_domains", []))
    user_agent: str = str(policy_raw.get("user_agent", "RFView-KBIngestionBot/0.1"))
    delay_seconds: float = float(policy_raw.get("delay_seconds", 1.5))

    if not domain_allowed(args.catalog_url, allowed_domains):
        print(f"[ERROR] Catalog URL domain is not in the allowed list: {args.catalog_url}", file=sys.stderr)
        return 2

    print(f"[INFO] Discovering products from: {args.catalog_url}", file=sys.stderr)
    result = await discover(
        catalog_url=args.catalog_url,
        allowed_domains=allowed_domains,
        user_agent=user_agent,
        delay_seconds=delay_seconds,
        url_pattern=args.url_pattern,
        max_links=args.max_links,
    )

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_file = output_dir / f"catalog_discovery_{ts}.json"
    out_file.write_text(json.dumps(result, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

    print(f"[INFO] Wrote discovery artifact: {out_file}")
    print(f"[INFO] Found {result['total_found']} product link(s)")

    if result["total_found"] == 0 and not result.get("success"):
        return 1
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Discover product links from a vendor catalog page.")
    parser.add_argument("--catalog-url", required=True, help="URL of the catalog/listing page to crawl")
    parser.add_argument("--url-pattern", default=None,
                        help="Optional regex to filter discovered links (e.g. '/products/p/')")
    parser.add_argument("--max-links", type=int, default=50,
                        help="Max product links to return (0 = unlimited)")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(run(parse_args())))
