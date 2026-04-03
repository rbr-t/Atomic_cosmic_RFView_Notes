#!/usr/bin/env python3
"""Validation guard for the Crawl4AI KB ingestion pilot.

This validator is safe to run in CI without a live crawl.
It checks:
- seed catalog URLs remain within the declared allowlist
- crawl-produced KB records carry mandatory provenance fields
- pilot output artifacts are blocked when validation findings exist
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import yaml


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_CONFIG = SCRIPT_DIR / "configs" / "vendor_seed_catalog.yaml"
DEFAULT_OUTPUTS = SCRIPT_DIR / "outputs"
DEFAULT_KB_ROOT = REPO_ROOT / "data" / "kb"

REQUIRED_PROVENANCE_FIELDS = [
    "crawled_at_utc",
    "crawl_success",
    "http_status",
    "source_domain",
    "content_sha256",
    "crawl_error",
]


SUSPICIOUS_TITLE_MARKERS = [
    "this website uses cookies",
    "cookie settings",
    "accept cookies",
    "privacy preference",
    "enable javascript",
    "access denied",
    "just a moment",
    "please wait",
    "403 forbidden",
    "404",
    "not found",
]


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def domain_allowed(url: str, allowed_domains: list[str]) -> bool:
    host = urlparse(url).netloc.lower()
    return any(host == domain or host.endswith(f".{domain}") for domain in allowed_domains)


def is_suspicious_title(title: str | None) -> bool:
    if not title:
        return True
    normalized = title.strip().lower()
    return any(marker in normalized for marker in SUSPICIOUS_TITLE_MARKERS)


def validate_catalog(config_path: Path) -> list[str]:
    findings: list[str] = []
    cfg = load_yaml(config_path)
    policy = cfg.get("crawl_policy", {})
    allowed_domains = list(policy.get("allowed_domains", []))
    vendors = cfg.get("vendors", {})

    if not allowed_domains:
        findings.append("catalog:allowed_domains is empty")

    for vendor_name, vendor_cfg in vendors.items():
        discovery_url = vendor_cfg.get("discovery_url")
        if discovery_url and not domain_allowed(discovery_url, allowed_domains):
            findings.append(f"catalog:{vendor_name}: discovery_url outside allowlist -> {discovery_url}")

        for product in vendor_cfg.get("products", []):
            product_url = product.get("product_url")
            part_number = product.get("part_number", "unknown")
            if not product_url:
                findings.append(f"catalog:{vendor_name}:{part_number}: missing product_url")
                continue
            if not domain_allowed(product_url, allowed_domains):
                findings.append(f"catalog:{vendor_name}:{part_number}: product_url outside allowlist -> {product_url}")

            extraction = product.get("extraction", {})
            if extraction and not extraction.get("selector_version"):
                findings.append(f"catalog:{vendor_name}:{part_number}: extraction.selector_version missing")

    return findings


def validate_kb_records(kb_root: Path) -> list[str]:
    findings: list[str] = []
    for vendor_dir in kb_root.iterdir():
        if not vendor_dir.is_dir() or vendor_dir.name.startswith("_"):
            continue
        devices_path = vendor_dir / "devices.json"
        if not devices_path.exists():
            continue
        try:
            records = load_json(devices_path)
        except Exception as exc:
            findings.append(f"kb:{devices_path}: invalid JSON -> {exc}")
            continue

        if not isinstance(records, list):
            findings.append(f"kb:{devices_path}: expected JSON array")
            continue

        for record in records:
            if not isinstance(record, dict):
                findings.append(f"kb:{devices_path}: non-object record encountered")
                continue

            provenance = record.get("ingestion_provenance")
            if provenance is None:
                continue

            device_id = record.get("device_id", "unknown_device")
            for field in REQUIRED_PROVENANCE_FIELDS:
                if field not in provenance:
                    findings.append(f"kb:{device_id}: missing provenance field '{field}'")

            http_status = provenance.get("http_status")
            if not isinstance(http_status, int) or http_status < 200 or http_status >= 400:
                findings.append(f"kb:{device_id}: unexpected http_status '{http_status}'")

            if is_suspicious_title(provenance.get("source_title_hint")):
                findings.append(f"kb:{device_id}: suspicious source_title_hint '{provenance.get('source_title_hint')}'")

            if not record.get("knowledge_confidence"):
                findings.append(f"kb:{device_id}: missing knowledge_confidence")

            if not record.get("datasheet_url"):
                findings.append(f"kb:{device_id}: missing datasheet_url")

    return findings


def validate_output_artifacts(outputs_dir: Path) -> list[str]:
    findings: list[str] = []
    if not outputs_dir.exists():
        return findings

    latest_by_vendor: dict[str, Path] = {}
    for artifact in sorted(outputs_dir.glob("*_pilot_run_*.json")):
        vendor = artifact.name.split("_pilot_run_", 1)[0]
        latest_by_vendor[vendor] = artifact

    for artifact in sorted(latest_by_vendor.values()):
        try:
            payload = load_json(artifact)
        except Exception as exc:
            findings.append(f"artifact:{artifact.name}: invalid JSON -> {exc}")
            continue

        context = payload.get("run_context", {})
        if "python_runtime_ready" not in context:
            findings.append(f"artifact:{artifact.name}: missing run_context.python_runtime_ready")
        if "crawl4ai_available" not in context:
            findings.append(f"artifact:{artifact.name}: missing run_context.crawl4ai_available")

        records = payload.get("records", [])
        validation = payload.get("validation", {})
        blocked = payload.get("blocked_for_auto_merge")

        if not isinstance(records, list):
            findings.append(f"artifact:{artifact.name}: records must be a list")
            continue

        bad_records = 0
        for record in records:
            device_id = record.get("device_id", "unknown_device")
            provenance = record.get("ingestion_provenance", {})
            record_has_blocker = False
            for field in REQUIRED_PROVENANCE_FIELDS:
                if field not in provenance:
                    findings.append(f"artifact:{artifact.name}:{device_id}: missing provenance field '{field}'")
                    record_has_blocker = True

            http_status = provenance.get("http_status")
            if not isinstance(http_status, int) or http_status < 200 or http_status >= 400:
                findings.append(f"artifact:{artifact.name}:{device_id}: unexpected http_status '{http_status}'")
                record_has_blocker = True

            if is_suspicious_title(provenance.get("source_title_hint")):
                findings.append(f"artifact:{artifact.name}:{device_id}: suspicious source_title_hint '{provenance.get('source_title_hint')}'")
                record_has_blocker = True

            if record.get("knowledge_confidence") == "low":
                record_has_blocker = True

            record_validation = validation.get(device_id)
            if record_validation is None:
                findings.append(f"artifact:{artifact.name}:{device_id}: missing validation entry")
                record_has_blocker = True
            elif record_validation:
                record_has_blocker = True

            if record_has_blocker:
                bad_records += 1

        if bad_records > 0 and blocked is not True:
            findings.append(f"artifact:{artifact.name}: auto-merge should be blocked when validation blockers exist")

    return findings


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Crawl4AI KB ingestion config, outputs, and crawler-produced records.")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--outputs-dir", default=str(DEFAULT_OUTPUTS))
    parser.add_argument("--kb-root", default=str(DEFAULT_KB_ROOT))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    findings = []
    findings.extend(validate_catalog(Path(args.config)))
    findings.extend(validate_kb_records(Path(args.kb_root)))
    findings.extend(validate_output_artifacts(Path(args.outputs_dir)))

    if findings:
        print("[FAIL] Crawl4AI KB ingestion validation failed:")
        for finding in findings:
            print(f" - {finding}")
        return 1

    print("[PASS] Crawl4AI KB ingestion validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
