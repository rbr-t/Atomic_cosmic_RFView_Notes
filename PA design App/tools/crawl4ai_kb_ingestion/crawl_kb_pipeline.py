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
import html
import io
import json
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urljoin, urlparse

import yaml

# Force UTF-8 output for Windows hosts where parent process consoles default to
# cp1252 (e.g., Shiny/R system2), which can crash Rich logger output.
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
KB_ROOT = REPO_ROOT / "data" / "kb"
VENDOR_DISPLAY_NAMES = {
    "ampleon": "Ampleon",
    "guerrilla_rf": "Guerrilla RF",
    "nxp": "NXP",
    "qorvo": "Qorvo",
}

DEFAULT_FIGURE_KEYWORDS = {
    "package": ["package", "outline", "pin connection", "pinning"],
    "layout": ["fixture", "layout", "component", "test circuit", "impedance"],
    "plot": ["gain", "efficiency", "power", "performance", "acpr", "linearity", "curve"],
}


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
    extraction: dict[str, Any] | None = None


@dataclass(frozen=True)
class VendorExtractionProfile:
    key: str
    display_name: str
    structured_section_builder: Callable[[list[dict[str, Any]], str], dict[str, Any]]
    app_note_templates: list[str] = field(default_factory=list)
    figure_keywords: dict[str, list[str]] = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)


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


def _clean_url_candidate(url: str) -> str:
    """Trim common trailing punctuation artifacts from regex-captured URLs."""
    return url.strip().strip("\"'()[]{}.,;")


def slugify(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("_") or "unknown"


def infer_vendor_key_from_url(url: str) -> str:
    host = urlparse(url).netloc.lower()
    host_key = host.replace("-", "_")
    for key in VENDOR_DISPLAY_NAMES:
        if key in host_key:
            return key
    host = host.replace("www.", "")
    return host.split(".")[0].replace("-", "_") if host else "unknown"


def infer_part_number_from_url(url: str) -> str:
    path = urlparse(url).path.rstrip("/")
    if not path:
        return "unknown"
    tail = path.split("/")[-1]
    tail = re.sub(r"\.(html?|pdf)$", "", tail, flags=re.IGNORECASE)
    tail = tail.replace("part", "").strip("-_")
    return tail or "unknown"


def infer_technology(text: str) -> str:
    t = text.lower()
    if "ldmos" in t:
        return "LDMOS"
    if re.search(r"\bgan[-\s]*sic\b", t):
        return "GaN-SiC"
    if re.search(r"\bgan[-\s]*si\b", t) or (re.search(r"\bgan\b", t) and re.search(r"\bsilicon\b", t)):
        return "GaN-Si"
    if "gaas" in t:
        return "GaAs"
    if re.search(r"\bsic\b", t):
        return "SiC"
    return "Other"


def infer_series(part_number: str) -> str | None:
    m = re.match(r"([A-Z]+\d+[A-Z0-9]*)", (part_number or "").upper())
    return m.group(1) if m else None


def infer_frequency_bounds(text: str) -> tuple[float | None, float | None]:
    # Matches patterns like "1.4 - 2.2 GHz" or "1800 to 2200 MHz"
    ghz_match = re.search(r"(\d+(?:\.\d+)?)\s*(?:-|to)\s*(\d+(?:\.\d+)?)\s*ghz", text, flags=re.IGNORECASE)
    if ghz_match:
        return float(ghz_match.group(1)) * 1000.0, float(ghz_match.group(2)) * 1000.0

    mhz_match = re.search(r"(\d+(?:\.\d+)?)\s*(?:-|to)\s*(\d+(?:\.\d+)?)\s*mhz", text, flags=re.IGNORECASE)
    if mhz_match:
        return float(mhz_match.group(1)), float(mhz_match.group(2))

    return None, None


def is_plausible_rf_value(param: str, value: float | int | None) -> bool:
    if value is None:
        return False
    try:
        numeric = float(value)
    except Exception:
        return False

    bounds = {
        "gain_db": (0.0, 45.0),
        "pae_pct": (0.0, 95.0),
        "drain_eff_pct": (0.0, 95.0),
        "vdd_v": (0.5, 100.0),
        "pout_w_cw": (0.01, 5000.0),
        "pout_dbm": (10.0, 80.0),
        "p1db_dbm": (10.0, 80.0),
        "ip3_dbm": (0.0, 90.0),
        "idd_a": (0.0, 200.0),
        "ropt_ohm": (0.01, 500.0),
        "freq_test_mhz": (1.0, 100000.0),
        "freq_min_mhz": (1.0, 100000.0),
        "freq_max_mhz": (1.0, 100000.0),
    }
    min_v, max_v = bounds.get(param, (-1.0e12, 1.0e12))
    return min_v <= numeric <= max_v


def extract_title(text: str) -> str | None:
    line = next((ln.strip() for ln in text.splitlines() if ln.strip()), None)
    if not line:
        return None
    return line[:140]


def is_suspicious_title(title: str | None) -> bool:
    if not title:
        return True

    normalized = title.strip().lower()
    suspicious_markers = [
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
    return any(marker in normalized for marker in suspicious_markers)


def python_runtime_ready() -> tuple[bool, str]:
    version = sys.version_info
    if (version.major, version.minor) >= (3, 14):
        return False, "Python 3.14+ is not yet supported by Crawl4AI dependency wheels in this workspace"
    if (version.major, version.minor) < (3, 12):
        return False, "Python 3.12+ is recommended for the Crawl4AI ingestion toolchain"
    return True, "runtime_compatible"


# ── PDF table extraction ───────────────────────────────────────────────────────
try:
    import pdfplumber  # type: ignore[import-not-found]
    HAS_PDFPLUMBER = True
except ImportError:
    HAS_PDFPLUMBER = False

try:
    import requests as _requests  # type: ignore[import-not-found]
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

# Maps RF parameter names → regex patterns that match table column headers
_RF_HEADER_MAP: list[tuple[str, list[str]]] = [
    ("pout_w_cw",       [r"output power.*cw", r"p_?out.*cw", r"pout\s*\(w\)"]),
    ("pout_dbm",        [r"p_?out.*dbm", r"output power.*dbm"]),
    ("gain_db",         [r"power gain", r"transducer gain", r"\bgain\b"]),
    ("pae_pct",         [r"power added efficiency", r"\bpae\b"]),
    ("drain_eff_pct",   [r"drain efficiency", r"\bde\b\s*%", r"efficiency.*%"]),
    ("vdd_v",           [r"supply voltage", r"drain.*supply", r"v_?dd"]),
    ("p1db_dbm",        [r"1.?db compression", r"p_?1db", r"op1db"]),
    ("ip3_dbm",         [r"ip3", r"oip3", r"third.order intercept"]),
    ("idd_a",           [r"quiescent current", r"drain current", r"i_?dd"]),
    ("ropt_ohm",        [r"r_?opt", r"optimum.*load.*resistance"]),
    ("freq_test_mhz",   [r"test frequency", r"freq.*mhz", r"frequency.*mhz"]),
]


def _parse_numeric(value: str) -> float | None:
    """Extract first number from a table cell string."""
    m = re.search(r"[-+]?\d+\.?\d*(?:[eE][-+]?\d+)?", str(value).replace(",", "."))
    return float(m.group()) if m else None


def _match_header(header: str) -> str | None:
    """Return the RF parameter key if header matches any known pattern."""
    h = header.lower().strip()
    for param, patterns in _RF_HEADER_MAP:
        if any(re.search(p, h) for p in patterns):
            return param
    return None


def extract_datasheet_candidates(page_text: str, base_url: str) -> list[str]:
    """Find likely datasheet URLs in HTML/markdown/text content.

    Returns ordered candidates, including non-.pdf endpoints that may redirect to a PDF.
    """
    candidates: list[str] = []

    patterns = [
        # Most direct links
        r'href=["\']([^"\']*(?:datasheet|data-sheet|document|download)[^"\']*)["\']',
        # Markdown links with datasheet-like anchor text
        r'\[[^\]]*(?:datasheet|data\s*sheet|download)[^\]]*\]\((https?://[^)\s]+)\)',
        # Absolute PDF URLs
        r'(https?://[^\s"\'<>]+\.pdf)',
        # Relative/absolute URLs containing datasheet cues (may not end with .pdf)
        r'(https?://[^\s"\'<>]*(?:datasheet|data-sheet|download|/d/)[^\s"\'<>]*)',
    ]

    for pat in patterns:
        for m in re.finditer(pat, page_text, re.IGNORECASE):
            url = _clean_url_candidate(m.group(1))
            if not url:
                continue
            if not url.startswith("http"):
                url = urljoin(base_url, url)
            if url not in candidates:
                candidates.append(url)

    # Prefer obvious PDF-like links first
    candidates.sort(key=lambda u: (0 if ".pdf" in u.lower() else 1, len(u)))
    return candidates


def rank_datasheet_candidates(candidate_urls: list[str], part_number: str, vendor_key: str) -> list[str]:
        part_lc = (part_number or "").lower()
        vendor_lc = (vendor_key or "").lower()

        def score(url: str) -> tuple[int, int, str]:
                clean = html.unescape(url or "")
                url_lc = clean.lower()
                value = 0
                if "datasheet" in url_lc or "data-sheet" in url_lc:
                    value += 60
                if "/documents/data-sheet/" in url_lc or "/docs/en/data-sheet/" in url_lc:
                    value += 45
                if part_lc and part_lc in url_lc:
                    value += 20
                if part_lc and f"{part_lc}ds.pdf" in url_lc:
                    value += 35
                if "ds.pdf" in url_lc:
                    value += 20
                if vendor_lc == "guerrilla_rf" and "products/datasheet" in url_lc:
                    value += 50
                if any(bad in url_lc for bad in ["rohs", "material", "mfgnote", "environmental", "quality", "iso", "conflict"]):
                    value -= 90
                if any(bad in url_lc for bad in ["privacy", "policy", "cookies", "terms", "media-download", "wp-assets", "/about/"]):
                    value -= 160
                if any(bad in url_lc for bad in [".png", ".jpg", ".jpeg", ".svg", "youtube", "linkedin", "facebook", "/news/"]):
                    value -= 220
                return (-value, len(clean), clean)

        deduped = list(dict.fromkeys(html.unescape(item) for item in candidate_urls if item))
        ranked = sorted(deduped, key=score)
        return ranked


def extract_page_summary_fields(page_text: str) -> dict[str, Any]:
        normalized = html.unescape(page_text or "")
        normalized = re.sub(r"\s+", " ", normalized)
        summary: dict[str, Any] = {}

        application_match = re.search(r"(?:targeting|for)\s+([^.]+?)\s+applications", normalized, flags=re.IGNORECASE)
        if application_match:
                applications = [item.strip(" ,") for item in re.split(r",|/| and ", application_match.group(1)) if item.strip()]
                if applications:
                        summary["application"] = applications

        if re.search(r"driver amplifier|linear driver", normalized, flags=re.IGNORECASE):
                summary["role"] = ["driver"]

        if re.search(r"power amplifier", normalized, flags=re.IGNORECASE) and "role" not in summary:
            summary["role"] = ["main"]

        vdd = _extract_param_from_text(normalized, [
                r"single\s+(\d+(?:\.\d+)?)\s*v\s+supply",
                r"operate\s+with\s+a\s+single\s+(\d+(?:\.\d+)?)\s*v\s+supply",
                r"(\d+(?:\.\d+)?)\s*v\s+suppl(?:y|ies)",
        ], min_v=1, max_v=65)
        if vdd is not None:
                summary["vdd_v"] = vdd

        p1db_dbm = _extract_param_from_text(normalized, [
                r"up to\s+(\d+(?:\.\d+)?)\s*dBm\s+of\s+OP1dB",
                r"(\d+(?:\.\d+)?)\s*dBm\s+of\s+OP1dB",
        ], min_v=0, max_v=60)
        if p1db_dbm is not None:
                summary["p1db_w"] = round(10 ** ((p1db_dbm - 30) / 10), 4)

        gain_db = _extract_param_from_text(normalized, [
            r"power gain[^\d]{0,40}(\d+(?:\.\d+)?)\s*dB",
                r"gain\s+of\s+(\d+(?:\.\d+)?)\s*dB",
                r"(\d+(?:\.\d+)?)\s*dB\s+gain",
        ], min_v=0, max_v=40)
        if gain_db is not None:
                summary["gain_db"] = gain_db

        if "gain_db" not in summary:
            small_signal_gain = _extract_param_from_text(normalized, [
                r"small signal gain[^\d]{0,40}(\d+(?:\.\d+)?)\s*dB",
            ], min_v=0, max_v=45)
            if small_signal_gain is not None:
                summary["gain_db"] = small_signal_gain

        package_dimensions = re.search(r"package dimensions:\s*([0-9.]+\s*x\s*[0-9.]+\s*x\s*[0-9.]+\s*mm)", normalized, flags=re.IGNORECASE)
        if package_dimensions:
            summary["package"] = package_dimensions.group(1)

        bias_vdd = _extract_param_from_text(normalized, [
            r"bias:[^\n]*?\bVD\s*=\s*(\d+(?:\.\d+)?)\s*V",
            r"\bVDD\s*=\s*(\d+(?:\.\d+)?)\s*V",
        ], min_v=1, max_v=65)
        if bias_vdd is not None:
            summary["vdd_v"] = bias_vdd

        return summary


def download_pdf_bytes(url: str, timeout: int = 15, _depth: int = 0) -> bytes | None:
    """Download a PDF and return raw bytes, or None on failure."""
    if not HAS_REQUESTS:
        return None
    if _depth > 1:
        return None
    try:
        resp = _requests.get(url, timeout=timeout, headers={"User-Agent": "RFView-KBIngestionBot/0.1"}, allow_redirects=True)
        if resp.status_code == 200 and b"%PDF" in resp.content[:8]:
            return resp.content

        ctype = (resp.headers.get("Content-Type") or "").lower()
        if resp.status_code == 200 and ("text/html" in ctype or "application/xhtml" in ctype):
            html = resp.text or ""
            # Try nested PDF links inside wrapper pages
            nested_pdf = None
            for pat in [
                r'href=["\']([^"\']+\.pdf(?:\?[^"\']*)?)["\']',
                r'(https?://[^\s"\'<>]+\.pdf(?:\?[^\s"\'<>]*)?)',
            ]:
                m = re.search(pat, html, re.IGNORECASE)
                if m:
                    nested_pdf = _clean_url_candidate(m.group(1))
                    break
            if nested_pdf:
                nested_pdf = urljoin(resp.url, nested_pdf)
                return download_pdf_bytes(nested_pdf, timeout=timeout, _depth=_depth + 1)
    except Exception:
        pass
    return None


def extract_params_from_pdf_bytes(pdf_bytes: bytes, part_number: str = "") -> dict[str, Any]:
    """Use pdfplumber to scan specification tables and extract RF electrical parameters.

    Returns a dict of extracted fields (may be partial / empty).
    """
    if not HAS_PDFPLUMBER or not pdf_bytes:
        return {}

    params: dict[str, Any] = {}
    pdf_io = io.BytesIO(pdf_bytes)

    try:
        with pdfplumber.open(pdf_io) as pdf:
            for page in pdf.pages[:12]:  # limit to first 12 pages
                for table in (page.extract_tables() or []):
                    if not table or len(table) < 2:
                        continue
                    # Row 0: headers, row 1+: values
                    headers = [str(c).strip() if c else "" for c in table[0]]
                    for row in table[1:]:
                        if not row:
                            continue
                        for col_idx, cell in enumerate(row):
                            if col_idx >= len(headers):
                                break
                            cell_str = str(cell).strip() if cell else ""
                            hdr = headers[col_idx]
                            param = _match_header(hdr)
                            if param and param not in params:
                                val = _parse_numeric(cell_str)
                                if val is not None and is_plausible_rf_value(param, val):
                                    params[param] = val
                    # Also scan two-column "Parameter | Value" style tables
                    if len(headers) >= 2:
                        for row in table[1:]:
                            if not row or len(row) < 2:
                                continue
                            param = _match_header(str(row[0]).strip())
                            if param and param not in params:
                                val = _parse_numeric(str(row[1]).strip())
                                if val is not None and is_plausible_rf_value(param, val):
                                    params[param] = val
    except Exception as exc:
        print(f"[WARN] PDF parse error for {part_number}: {exc}", file=sys.stderr)

    return params


def _extract_param_from_text(text: str, patterns: list[str], min_v: float | None = None, max_v: float | None = None) -> float | None:
    """Find first plausible numeric capture from text using ordered regex patterns."""
    for pat in patterns:
        m = re.search(pat, text, flags=re.IGNORECASE)
        if not m:
            continue
        try:
            v = float(m.group(1))
        except Exception:
            continue
        if min_v is not None and v < min_v:
            continue
        if max_v is not None and v > max_v:
            continue
        return v
    return None


def extract_params_from_pdf_text(pdf_bytes: bytes, part_number: str = "") -> dict[str, Any]:
    """Fallback extraction from full PDF text when table extraction is sparse."""
    if not HAS_PDFPLUMBER or not pdf_bytes:
        return {}

    try:
        with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
            text = "\n".join((p.extract_text() or "") for p in pdf.pages[:16])
    except Exception as exc:
        print(f"[WARN] PDF text parse error for {part_number}: {exc}", file=sys.stderr)
        return {}

    if not text.strip():
        return {}

    params: dict[str, Any] = {}

    gain = _extract_param_from_text(text, [
        r"PowerGain\s+\w+\s+[\-0-9.]+\s+([\-0-9.]+)\s+[\-0-9.]+\s+dB",
        r"(?:power\s*gain|transducer\s*gain|\bgain\b)\D{0,40}(\d{1,2}(?:\.\d+)?)\s*dB",
    ], min_v=0, max_v=45)
    if gain is not None:
        params["gain_db"] = gain

    pae = _extract_param_from_text(text, [
        r"(?:power\s+added\s+efficiency|\bPAE\b)\D{0,30}(\d{1,2}(?:\.\d+)?)\s*%",
    ], min_v=1, max_v=95)
    if pae is not None:
        params["pae_pct"] = pae

    de = _extract_param_from_text(text, [
        r"DrainEfficiency.*?[\-0-9.]+\s+([\-0-9.]+)\s+(?:[\-0-9.]+|—)\s*%",
        r"(?:drain\s*efficiency|\bDE\b)\D{0,40}(\d{1,2}(?:\.\d+)?)\s*%",
    ], min_v=1, max_v=95)
    if de is not None:
        params["drain_eff_pct"] = de

    vdd = _extract_param_from_text(text, [
        r"(?:supply\s+voltage|drain\s+voltage|\bVDD\b)\D{0,20}(\d{1,3}(?:\.\d+)?)\s*V",
    ], min_v=1, max_v=150)
    if vdd is not None:
        params["vdd_v"] = vdd

    pout_w = _extract_param_from_text(text, [
        r"(?:output\s+power|\bPout\b)\D{0,30}(\d{1,4}(?:\.\d+)?)\s*W",
    ], min_v=0.1, max_v=5000)
    if pout_w is not None:
        params["pout_w_cw"] = pout_w

    pout_dbm = _extract_param_from_text(text, [
        r"(?:output\s+power|\bPout\b)\D{0,30}(\d{2,3}(?:\.\d+)?)\s*dBm",
    ], min_v=10, max_v=80)
    if pout_dbm is not None:
        params["pout_dbm"] = pout_dbm

    p1db = _extract_param_from_text(text, [
        r"(?:1\s*dB\s+compression|\bP1dB\b|\bOP1dB\b)\D{0,30}(\d{2,3}(?:\.\d+)?)\s*dBm",
    ], min_v=10, max_v=80)
    if p1db is not None:
        params["p1db_dbm"] = p1db

    ropt = _extract_param_from_text(text, [
        r"(?:\bRopt\b|optimum\s+load\s+resistance)\D{0,20}(\d{1,3}(?:\.\d+)?)\s*(?:ohm|Ω)",
    ], min_v=0.1, max_v=200)
    if ropt is not None:
        params["ropt_ohm"] = ropt

    f_ghz = re.search(r"(\d+(?:\.\d+)?)\s*(?:-|to)\s*(\d+(?:\.\d+)?)\s*GHz", text, flags=re.IGNORECASE)
    if f_ghz:
        try:
            params["freq_min_mhz"] = float(f_ghz.group(1)) * 1000.0
            params["freq_max_mhz"] = float(f_ghz.group(2)) * 1000.0
        except Exception:
            pass
    else:
        f_mhz = re.search(r"(\d+(?:\.\d+)?)\s*(?:-|to)\s*(\d+(?:\.\d+)?)\s*MHz", text, flags=re.IGNORECASE)
        if f_mhz:
            try:
                params["freq_min_mhz"] = float(f_mhz.group(1))
                params["freq_max_mhz"] = float(f_mhz.group(2))
            except Exception:
                pass

    return params


def extract_package_identifier(full_text: str, part_number: str = "") -> str | None:
    normalized = _normalize_pdf_parse_text(full_text or "")
    patterns = []
    if part_number:
        patterns.extend([
            rf"\b{re.escape(part_number)}\b.*?\b(SOT\d{{4}}-\d+)\b",
            rf"\b{re.escape(part_number)}\b.*?\b((?:P?QFN|DFN|LGA)[A-Z0-9.-]*)\b",
            rf"\b{re.escape(part_number)}[A-Z0-9-]*\b.*?\b((?:TO|NI)--[A-Z0-9-]+)\b",
        ])
    patterns.extend([
        r"\b(SOT\d{4}-\d+)\b",
        r"\b((?:P?QFN|DFN|LGA)[A-Z0-9.-]*)\b",
        r"\b((?:TO|NI)--[A-Z0-9-]+)\b",
    ])
    for pattern in patterns:
        match = re.search(pattern, normalized, flags=re.IGNORECASE | re.DOTALL)
        if match:
            return match.group(1).upper()
    return None


def extract_pdf_full_text(pdf_bytes: bytes) -> tuple[str, int]:
    if not HAS_PDFPLUMBER or not pdf_bytes:
        return "", 0
    try:
        with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
            pages = [(p.extract_text() or "") for p in pdf.pages]
            return "\n".join(pages), len(pdf.pages)
    except Exception:
        return "", 0


def extract_document_metadata(full_text: str, page_count: int, pdf_url: str | None, part_number: str) -> dict[str, Any]:
    first_lines = [ln.strip() for ln in full_text.splitlines() if ln.strip()][:12]
    doc_number = None
    revision = None
    title = None
    m = re.search(r"Document\s*Number\s*:?\s*([A-Z0-9-]+)", full_text, flags=re.IGNORECASE)
    if m:
        doc_number = m.group(1)
    m = re.search(r"\bRev\.?\s*([A-Za-z0-9.,/-]+)", full_text, flags=re.IGNORECASE)
    if m:
        revision = m.group(1)
    if first_lines:
        title = " | ".join(first_lines[:4])[:260]
    return {
        "document_number": doc_number,
        "revision": revision,
        "page_count": page_count,
        "pdf_url": pdf_url,
        "title": title,
        "part_number_detected": part_number,
    }


def extract_section_block(full_text: str, start_heading: str, stop_headings: list[str]) -> str | None:
    start = re.search(start_heading, full_text, flags=re.IGNORECASE)
    if not start:
        return None
    tail = full_text[start.end():]
    stop_positions = []
    for h in stop_headings:
        m = re.search(h, tail, flags=re.IGNORECASE)
        if m:
            stop_positions.append(m.start())
    end_pos = min(stop_positions) if stop_positions else min(len(tail), 2000)
    return tail[:end_pos].strip() or None


def extract_typical_applications(full_text: str) -> list[str]:
    block = extract_section_block(full_text, r"Typical\s*Applications", [r"Figure\s*1", r"Table\s*1", r"Features"]) or ""
    items = re.findall(r"[•\-]\s*([^\n]+)", block)
    cleaned = []
    for item in items:
        text = _normalize_pdf_parse_text(item)
        text = text.replace("orsea", "or-sea")
        text = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", text)
        text = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", " ", text)
        text = re.sub(r"\s+", " ", text).strip(" -")
        if text:
            cleaned.append(text)
    return cleaned


def _normalize_pdf_parse_text(text: str) -> str:
    replacements = {
        "": "u",
        "": "ohm",
        "": "C",
        "": "in",
        "": "x",
        "": "diameter ",
        "": " • ",
        "–": "-",
        "—": "-",
        "−": "-",
    }
    normalized = text or ""
    for src, dst in replacements.items():
        normalized = normalized.replace(src, dst)
    normalized = normalized.replace("--", "-")
    return normalized


def _extract_block_lines(full_text: str, start_heading: str, stop_headings: list[str]) -> list[str]:
    block = extract_section_block(full_text, start_heading, stop_headings) or ""
    if not block:
        return []
    normalized = _normalize_pdf_parse_text(block)
    lines = [re.sub(r"\s+", " ", line).strip() for line in normalized.splitlines()]
    return [line for line in lines if line]


def parse_nxp_variants(full_text: str) -> list[dict[str, Any]]:
    lines = _extract_block_lines(full_text, r"Table\s*6\.OrderingInformation", [r"TYPICALCHARACTERISTICS", r"Figure\s*2\."])
    variants: list[dict[str, Any]] = []
    for line in lines:
        if any(token in line for token in ["Device TapeandReelInformation Package", "Measurementmadewithdevice", "RFDeviceData", "NXPSemiconductors"]):
            continue
        m = re.match(r"^([A-Z0-9-]+)\s+([A-Z]{2,}--[A-Z0-9-]+)\s+(.+)$", line)
        if m:
            variants.append({
                "type_number": m.group(1),
                "package": m.group(2),
                "description": re.sub(r"\s+", " ", m.group(3)).strip(),
            })
            continue
        m = re.match(r"^([A-Z0-9-]+)\s+(.+?)\s+([A-Z]{2}-\d+[A-Z0-9-]+)$", line)
        if not m:
            continue
        variants.append({
            "type_number": m.group(1),
            "package": m.group(3),
            "description": re.sub(r"\s+", " ", m.group(2)).strip(),
        })
    return variants


def parse_nxp_test_circuits(full_text: str) -> list[dict[str, Any]]:
    lines = _extract_block_lines(full_text, r"Table\s*7\.[^\n]+", [r"TYPICALCHARACTERISTICS", r"Figure\s*6\."])
    bom: list[dict[str, Any]] = []
    for line in lines:
        if any(token in line for token in [
            "Part Description PartNumber Manufacturer",
            "RFDeviceData",
            "NXPSemiconductors",
        ]):
            continue
        m = re.match(
            r"^([A-Za-z0-9,.*+/()-]+)\s+(.+?)\s+([A-Z0-9][A-Z0-9()./_-]+)\s+([A-Za-z][A-Za-z0-9-]*(?:\s+[A-Za-z][A-Za-z0-9-]*)?)$",
            line,
        )
        if not m:
            continue
        bom.append({
            "ref": m.group(1),
            "type": re.sub(r"\s+", " ", m.group(2)).strip(),
            "value": m.group(3),
            "vendor": re.sub(r"\s+", " ", m.group(4)).strip(),
        })

    if not bom:
        return []

    normalized_text = _normalize_pdf_parse_text(full_text)
    board_size = None
    size_match = re.search(
        r"PRODUCTIONFIXTURE-([0-9.]+)in\s*x\s*([0-9.]+)in\s*\(([0-9.]+)cm\s*x\s*([0-9.]+)cm\)",
        re.sub(r"\s+", "", normalized_text),
        flags=re.IGNORECASE,
    )
    if size_match:
        board_size = f"{round(float(size_match.group(3)) * 10):.0f} x {round(float(size_match.group(4)) * 10):.0f}"

    substrate = None
    thickness_mm = None
    for item in bom:
        if item.get("ref") != "PCB":
            continue
        substrate_match = re.search(r"([A-Za-z]+\d*)\s*([0-9.]+)in", item.get("type") or "", flags=re.IGNORECASE)
        if substrate_match:
            substrate = substrate_match.group(1)
            thickness_mm = round(float(substrate_match.group(2)) * 25.4, 3)
        else:
            substrate = item.get("type")
        break

    figure = "Figure 5. MMRF1050H Production Fixture Component Layout - 950 MHz"
    return [{
        "freq_mhz": 950,
        "pcb_substrate": substrate or "Arlon 450",
        "pcb_thickness_mm": thickness_mm or 0.762,
        "pcb_size_mm": board_size or "102 x 127",
        "figure": figure,
        "bom": bom,
    }]


def _parse_complex_ohms(value: str) -> tuple[float | None, float | None]:
    cleaned = _normalize_pdf_parse_text(value).replace("ohm", "").replace(" ", "")
    match = re.match(r"^([+-]?\d+(?:\.\d+)?)?([+-])j(\d+(?:\.\d+)?)$", cleaned, flags=re.IGNORECASE)
    if match:
        real = float(match.group(1)) if match.group(1) is not None else 0.0
        imag = float(match.group(3))
        if match.group(2) == "-":
            imag *= -1.0
        return real, imag
    try:
        return float(cleaned), 0.0
    except Exception:
        return None, None


def parse_nxp_impedance_table(full_text: str) -> list[dict[str, Any]]:
    lines = _extract_block_lines(
        full_text,
        r"Band[-\s]*SpecificOptimizedPerformanceandImpedanceInformation",
        [r"Figure\s*10\.", r"PACKAGEINFORMATION"],
    )
    rows: list[dict[str, Any]] = []
    for line in lines:
        m = re.match(r"^(\d{3,4})\s+([0-9.+\-jJ]+)\s+([0-9.+\-jJ]+)$", line)
        if not m:
            continue
        zs_r, zs_x = _parse_complex_ohms(m.group(2))
        zl_r, zl_x = _parse_complex_ohms(m.group(3))
        rows.append({
            "freq_mhz": float(m.group(1)),
            "condition": "measured_impedance",
            "zs_r": zs_r,
            "zs_x": zs_x,
            "zl_r": zl_r,
            "zl_x": zl_x,
            "figure": "Figure 10. Series Equivalent Source and Load Impedance",
        })
    return rows


def parse_nxp_dc_characteristics(full_text: str) -> dict[str, Any] | None:
    lines = _extract_block_lines(full_text, r"Table\s*4\.ElectricalCharacteristics", [r"\(continued\)", r"Table\s*5\."])
    params: list[dict[str, Any]] = []
    current_condition = ""
    for line in lines:
        if line in {"OffCharacteristics(4)", "OnCharacteristics", "DynamicCharacteristics(4)"}:
            current_condition = line
            continue
        patterns = [
            (r"^GateThresholdVoltage\(4\)\s+(VGS\(th\))\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+Vdc$", "gate threshold voltage", "V"),
            (r"^GateQuiescentVoltage\(5\)\s+(VGS\(Q\))\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+Vdc$", "gate quiescent voltage", "V"),
            (r"^Drain-SourceOn-Voltage\(4\)\s+(VDS\(on\))\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+Vdc$", "drain-source on voltage", "V"),
            (r"^ReverseTransferCapacitance\s+(Crss)\s+(-|[-0-9.]+)\s+([-0-9.]+)\s+(-|[-0-9.]+)\s+pF$", "reverse transfer capacitance", "pF"),
        ]
        for pat, parameter, unit in patterns:
            m = re.match(pat, line)
            if not m:
                continue
            symbol, min_v, typ_v, max_v = m.groups()
            params.append({
                "symbol": symbol,
                "parameter": parameter,
                "conditions": current_condition,
                "min": None if min_v == "-" else float(min_v),
                "typ": None if typ_v == "-" else float(typ_v),
                "max": None if max_v == "-" else float(max_v),
                "unit": unit,
            })
            break
    if not params:
        return None
    return {
        "test_conditions": "Extracted from datasheet Table 4 electrical characteristics (TA=25 C unless otherwise noted)",
        "params": params,
    }


def parse_nxp_rf_characteristics(full_text: str) -> dict[str, Any] | None:
    lines = _extract_block_lines(full_text, r"FunctionalTests\(1\)", [r"Table\s*5\.LoadMismatch", r"Table\s*6\.OrderingInformation"])
    params: list[dict[str, Any]] = []
    test_conditions = ""
    for line in lines:
        if line.startswith("FunctionalTests(1)"):
            test_conditions = line
            continue
        patterns = [
            (r"^PowerGain\s+(Gps)\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+dB$", "power gain", "dB"),
            (r"^DrainEfficiency\s+([^\s]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+(-|[-0-9.]+)\s+%$", "drain efficiency", "%"),
            (r"^InputReturnLoss\s+(IRL)\s+(-|[-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+dB$", "input return loss", "dB"),
        ]
        for pat, parameter, unit in patterns:
            m = re.match(pat, line)
            if not m:
                continue
            symbol, min_v, typ_v, max_v = m.groups()
            params.append({
                "symbol": symbol,
                "parameter": parameter,
                "conditions": test_conditions,
                "min": None if min_v == "-" else float(min_v),
                "typ": None if typ_v == "-" else float(typ_v),
                "max": None if max_v == "-" else float(max_v),
                "unit": unit,
            })
            break
    if not params:
        return None
    return {
        "test_conditions": test_conditions,
        "test_note": "Extracted from datasheet functional test rows in Table 4 (continued).",
        "params": params,
    }


def _clean_figure_caption(raw_caption: str) -> str:
    caption = re.sub(r"\s+", " ", raw_caption or "").strip(" .:-")
    if not caption:
        return "Datasheet figure"
    caption = re.sub(r"(?<=[A-Za-z])versus(?=[A-Za-z])", " versus ", caption, flags=re.IGNORECASE)
    caption = re.sub(r"(?<=[A-Za-z])and(?=[A-Z])", " and ", caption)
    caption = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", caption)
    caption = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", " ", caption)
    caption = re.sub(r"(\d+)\s*([GMK])\s+Hz\b", r"\1 \2Hz", caption)
    caption = re.sub(r"\b([GMK])\s+Hz\b", r"\1Hz", caption)
    caption = re.sub(r"Layout-(\d)", r"Layout - \1", caption)
    caption = re.sub(r"\s+", " ", caption).strip(" .:-")
    return caption or "Datasheet figure"


def _categorize_figure_asset(caption: str, profile: VendorExtractionProfile) -> str:
    caption_lc = (caption or "").lower()
    for category in ("package", "layout", "plot"):
        keywords = profile.figure_keywords.get(category, [])
        if any(token in caption_lc for token in keywords):
            return category
    return "plot"


def extract_graphical_assets(vendor: str, part_number: str, pdf_bytes: bytes | None, profile: VendorExtractionProfile) -> dict[str, Any] | None:
    if not HAS_PDFPLUMBER or not pdf_bytes:
        return None
    out_dir = KB_ROOT / vendor / "_extracted" / slugify(part_number)
    out_dir.mkdir(parents=True, exist_ok=True)
    assets: list[dict[str, Any]] = []
    seen_assets: set[tuple[str, int, str]] = set()
    try:
        with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
            for idx, page in enumerate(pdf.pages):
                page_num = idx + 1
                page_text = _normalize_pdf_parse_text(page.extract_text() or "")
                matches: list[tuple[str, str]] = []
                for fig_match in re.finditer(r"Figure\s*(\d+)\.\s*([^\n]+)", page_text, flags=re.IGNORECASE):
                    figure_no = fig_match.group(1)
                    caption = _clean_figure_caption(fig_match.group(2))
                    matches.append((f"Figure {figure_no}", caption))
                if "PACKAGEINFORMATION" in re.sub(r"\s+", "", page_text).upper():
                    matches.append((f"Package page {page_num}", "Package information / outline"))
                if not matches:
                    continue
                image_name = f"{slugify(part_number)}_page_{page_num}.png"
                image_path = out_dir / image_name
                page.to_image(resolution=110).save(str(image_path), format="PNG")
                rel_path = str(image_path.relative_to(REPO_ROOT)).replace("\\", "/")
                for figure_label, caption in matches:
                    asset_key = (figure_label, page_num, caption)
                    if asset_key in seen_assets:
                        continue
                    seen_assets.add(asset_key)
                    category = _categorize_figure_asset(caption, profile)
                    assets.append({
                        "fig": figure_label,
                        "caption": caption,
                        "page": page_num,
                        "category": category,
                        "image_path": rel_path,
                    })
    except Exception as exc:
        print(f"[WARN] Graphical asset extraction failed for {part_number}: {exc}", file=sys.stderr)
        return None

    if not assets:
        return None

    curve_assets = [asset for asset in assets if asset["category"] == "plot"]
    layout_assets = [asset for asset in assets if asset["category"] == "layout"]
    package_assets = [asset for asset in assets if asset["category"] == "package"]
    return {
        "note": "Hover thumbnails open extracted datasheet figure pages for closer inspection.",
        "assets": assets,
        "cw_curves": curve_assets,
        "layout_figures": layout_assets,
        "package_figures": package_assets,
    }


def extract_table_blocks_from_text(full_text: str) -> list[dict[str, Any]]:
    matches = list(re.finditer(r"(Table\s*\d+\.[^\n]+)", full_text, flags=re.IGNORECASE))
    blocks: list[dict[str, Any]] = []
    for idx, m in enumerate(matches):
        start = m.start()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else min(len(full_text), start + 5000)
        title = re.sub(r"\s+", " ", m.group(1)).strip()
        content = re.sub(r"\s+", " ", full_text[start:end]).strip()
        blocks.append({
            "title": title,
            "content": content[:6000],
        })
    return blocks


def extract_app_notes_from_page(page_text: str, base_url: str) -> list[dict[str, str]]:
    notes: list[dict[str, str]] = []
    for m in re.finditer(r'href=["\']([^"\']*(?:application-note|app-note|AN\d+)[^"\']*)["\']', page_text, flags=re.IGNORECASE):
        url = _clean_url_candidate(m.group(1))
        if not url.startswith("http"):
            url = urljoin(base_url, url)
        title_m = re.search(r"(AN\d+[A-Z0-9-]*)", url, flags=re.IGNORECASE)
        title = title_m.group(1) if title_m else Path(urlparse(url).path).name
        item = {"title": title, "url": url}
        if item not in notes:
            notes.append(item)
    return notes


def extract_app_notes_from_text(full_text: str, profile: VendorExtractionProfile) -> list[dict[str, str]]:
    notes: list[dict[str, str]] = []
    for m in re.finditer(r"\b(AN\d{3,5}[A-Z0-9-]*)\s*:?\s*([^\n•]{3,120})", full_text, flags=re.IGNORECASE):
        code = m.group(1).upper()
        title = re.sub(r"\s+", " ", m.group(2)).strip(" :-")
        urls = [template.format(code=code) for template in profile.app_note_templates]
        item = {"title": f"{code} — {title}" if title else code, "url": urls[0] if urls else ""}
        if item not in notes:
            notes.append(item)
    return notes[:12]


def save_pdf_artifacts(vendor: str, part_number: str, pdf_bytes: bytes | None, full_text: str, table_blocks: list[dict[str, Any]]) -> dict[str, str]:
    out_dir = KB_ROOT / vendor / "_extracted" / slugify(part_number)
    out_dir.mkdir(parents=True, exist_ok=True)
    paths: dict[str, str] = {}
    if pdf_bytes:
        pdf_path = out_dir / f"{slugify(part_number)}_datasheet.pdf"
        pdf_path.write_bytes(pdf_bytes)
        paths["datasheet_file"] = str(pdf_path.relative_to(REPO_ROOT)).replace("\\", "/")
    if full_text:
        txt_path = out_dir / f"{slugify(part_number)}_datasheet_text.txt"
        txt_path.write_text(full_text, encoding="utf-8")
        paths["datasheet_text_file"] = str(txt_path.relative_to(REPO_ROOT)).replace("\\", "/")
    if table_blocks:
        tbl_path = out_dir / f"{slugify(part_number)}_table_blocks.json"
        tbl_path.write_text(json.dumps(table_blocks, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
        paths["datasheet_tables_file"] = str(tbl_path.relative_to(REPO_ROOT)).replace("\\", "/")
    return paths


def build_generic_structured_sections_from_blocks(table_blocks: list[dict[str, Any]], full_text: str) -> dict[str, Any]:
    sections: dict[str, Any] = {}
    for block in table_blocks:
        title = (block.get("title") or "").lower()
        content = block.get("content") or ""
        if "maximum ratings" in title:
            sections.setdefault("limiting_values", {})
            m = re.search(r"Drain[-\u2013 ]*SourceVoltage\s+\w+\s+[\-0-9.,+]+\s*,\+?(\d+(?:\.\d+)?)\s+V", content, flags=re.IGNORECASE)
            if m:
                sections["limiting_values"]["vds_max_v"] = float(m.group(1))
            m = re.search(r"Gate[-\u2013 ]*SourceVoltage\s+\w+\s+(-?\d+(?:\.\d+)?)\s*,\+?(\d+(?:\.\d+)?)\s+V", content, flags=re.IGNORECASE)
            if m:
                sections["limiting_values"]["vgs_min_v"] = float(m.group(1))
                sections["limiting_values"]["vgs_max_v"] = float(m.group(2))
            m = re.search(r"OperatingJunctionTemperatureRange.*?(\d+(?:\.\d+)?)\s*[°\u00b0]?C", content, flags=re.IGNORECASE)
            if m:
                sections["limiting_values"]["tj_max_c"] = float(m.group(1))
        elif "thermal characteristics" in title:
            m = re.search(r"ThermalImpedance.*?([0-9.]+)\s*[°\u00b0]?C/W", content, flags=re.IGNORECASE)
            if m:
                sections["thermal"] = {"rth_jc_k_per_w": float(m.group(1))}
        elif "esd" in title:
            esd = {}
            m = re.search(r"HumanBodyModel.*?Class\s*([A-Za-z0-9]+).*?(\d+V)", content, flags=re.IGNORECASE)
            if m:
                esd["hbm_class"] = m.group(1)
                esd["hbm_note"] = f"passes {m.group(2)}"
            m = re.search(r"ChargeDeviceModel.*?Class\s*([A-Za-z0-9]+).*?(\d+V)", content, flags=re.IGNORECASE)
            if m:
                esd["cdm_class"] = m.group(1)
                esd["cdm_note"] = f"passes {m.group(2)}"
            if esd:
                sections["esd"] = esd
        elif "electrical characteristics" in title:
            dc_params = []
            rf_params = []
            patterns = [
                (r"PowerGain\s+(\w+)\s+([\-0-9.]+)\s+([\-0-9.]+)\s+([\-0-9.]+)\s+dB", "power gain", "dB", rf_params),
                (r"DrainEfficiency\s+[^\s]+\s+([\-0-9.]+)\s+([\-0-9.]+)\s+([\-0-9.]+|—)\s+%", "drain efficiency", "%", rf_params),
                (r"InputReturnLoss\s+(\w+)\s+([\-0-9.]+|—)\s+([\-0-9.]+)\s+([\-0-9.]+)\s+dB", "input return loss", "dB", rf_params),
                (r"GateThresholdVoltage.*?(VGS\(th\))\s+([\-0-9.]+)\s+([\-0-9.]+)\s+([\-0-9.]+)\s+V", "gate threshold voltage", "V", dc_params),
                (r"GateQuiescentVoltage.*?(VGS\(Q\))\s+([\-0-9.]+)\s+([\-0-9.]+)\s+([\-0-9.]+)\s+V", "gate quiescent voltage", "V", dc_params),
            ]
            for pat, parameter, unit, bucket in patterns:
                for m in re.finditer(pat, content, flags=re.IGNORECASE):
                    groups = m.groups()
                    if len(groups) == 4:
                        symbol, min_v, typ_v, max_v = groups
                    else:
                        continue
                    bucket.append({
                        "symbol": symbol,
                        "parameter": parameter,
                        "conditions": "",
                        "min": None if min_v == "—" else float(min_v),
                        "typ": None if typ_v == "—" else float(typ_v),
                        "max": None if max_v == "—" else float(max_v),
                        "unit": unit,
                    })
            if dc_params:
                sections["dc_characteristics"] = {
                    "test_conditions": "Extracted from datasheet electrical characteristics table",
                    "params": dc_params,
                }
            if rf_params:
                sections["rf_characteristics"] = {
                    "test_conditions": "Extracted from datasheet electrical/functional test table",
                    "params": rf_params,
                }
        elif "load mismatch" in title or "ruggedness" in title:
            m = re.search(r"(\d+)\s*WPeak.*?(\d+)\s+NoDevice", content, flags=re.IGNORECASE)
            if m:
                sections["ruggedness"] = {
                    "vswr": 20,
                    "pout_cw_w": float(m.group(1)),
                    "note": "No device degradation in load mismatch test",
                }
        elif "ordering information" in title:
            rows = []
            for m in re.finditer(r"([A-Z0-9-]+)\s+.*?\s+([A-Z]{2}[-\u2013A-Z0-9]+(?:-\d+[A-Z]*)?)", content, flags=re.IGNORECASE):
                rows.append({"type_number": m.group(1), "package": m.group(2), "description": "Ordering information from datasheet"})
            if rows:
                sections["variants"] = rows[:10]
                if "package" not in sections:
                    sections["package"] = rows[0].get("package")

    if "rf_characteristics" in sections:
        for p in sections["rf_characteristics"].get("params", []):
            if p.get("parameter") == "power gain" and p.get("typ") is not None:
                sections["gain_db"] = p["typ"]
            if p.get("parameter") == "drain efficiency" and p.get("typ") is not None:
                sections["drain_eff_pct"] = p["typ"]
            if p.get("parameter") == "input return loss" and p.get("typ") is not None:
                sections["input_rl_db"] = p["typ"]
    return sections


def extract_application_list(full_text: str, start_heading: str, stop_headings: list[str]) -> list[str]:
    block = extract_section_block(full_text, start_heading, stop_headings) or ""
    if not block:
        return []
    normalized = _normalize_pdf_parse_text(block)
    normalized = re.sub(r"\s+", " ", normalized)
    bullet_items = [
        re.sub(r"\s+", " ", item).strip(" -")
        for item in re.findall(r"[•]\s*([^•]+?)(?=(?:[•]|$))", normalized)
    ]
    if bullet_items:
        return [item for item in bullet_items if 2 <= len(item) <= 40]
    return []


def parse_ampleon_variants(full_text: str) -> list[dict[str, Any]]:
    block = extract_section_block(full_text, r"Table\s*3\.\s*Ordering information", [r"4\.\s*Limiting values", r"Table\s*4\."]) or ""
    normalized = _normalize_pdf_parse_text(block)
    variants: list[dict[str, Any]] = []
    for match in re.finditer(r"\b([A-Z0-9-]{6,})\b\s+-\s+(.+?)\s+\b(SOT\d{4}-\d+)\b", normalized, flags=re.IGNORECASE):
        variants.append({
            "type_number": match.group(1).upper(),
            "package": match.group(3).upper(),
            "description": re.sub(r"\s+", " ", match.group(2)).strip(" ;"),
        })
    return variants


def parse_ampleon_rf_summary(full_text: str) -> dict[str, Any]:
    block = extract_section_block(full_text, r"Table\s*7\.\s*RF characteristics", [r"7\.\s*Test information", r"Table\s*8\."]) or ""
    normalized = _normalize_pdf_parse_text(block)
    summary: dict[str, Any] = {}
    gain_match = re.search(r"power gain\s+P\s*=\s*35\s*dBm\s+([0-9.]+)\s+([0-9.]+)\s+-\s+dB", normalized, flags=re.IGNORECASE)
    if gain_match:
        summary["gain_db"] = float(gain_match.group(2))
    eff_match = re.search(r"drain efficiency\s+P\s*=\s*35\s*dBm\s+([0-9.]+)\s+([0-9.]+)\s+-\s+%", normalized, flags=re.IGNORECASE)
    if eff_match:
        summary["drain_eff_pct"] = float(eff_match.group(2))
    vdd_match = re.search(r"V\s*=\s*(\d+(?:\.\d+)?)\s*V;\s*I\s*=\s*\d+\s*mA", normalized, flags=re.IGNORECASE)
    if vdd_match:
        summary["vdd_v"] = float(vdd_match.group(1))
    return summary


def build_nxp_structured_sections_from_blocks(table_blocks: list[dict[str, Any]], full_text: str) -> dict[str, Any]:
    sections = build_generic_structured_sections_from_blocks(table_blocks, full_text)

    nxp_variants = parse_nxp_variants(full_text)
    if nxp_variants:
        sections["variants"] = nxp_variants
        if "package" not in sections:
            sections["package"] = nxp_variants[0].get("package")

    nxp_dc = parse_nxp_dc_characteristics(full_text)
    if nxp_dc:
        sections["dc_characteristics"] = nxp_dc

    nxp_rf = parse_nxp_rf_characteristics(full_text)
    if nxp_rf:
        sections["rf_characteristics"] = nxp_rf

    nxp_test_circuits = parse_nxp_test_circuits(full_text)
    if nxp_test_circuits:
        sections["test_circuits"] = nxp_test_circuits

    nxp_impedance_rows = parse_nxp_impedance_table(full_text)
    if nxp_impedance_rows:
        sections["load_pull_table"] = nxp_impedance_rows
        sections["impedance_ref_plane"] = (
            "Measured at the package reference plane in NXP tuned fixtures; "
            "Zsource is gate-to-gate and Zload is drain-to-drain."
        )

    if "rf_characteristics" in sections:
        for p in sections["rf_characteristics"].get("params", []):
            if p.get("parameter") == "power gain" and p.get("typ") is not None:
                sections["gain_db"] = p["typ"]
            if p.get("parameter") == "drain efficiency" and p.get("typ") is not None:
                sections["drain_eff_pct"] = p["typ"]
            if p.get("parameter") == "input return loss" and p.get("typ") is not None:
                sections["input_rl_db"] = p["typ"]
    return sections


def build_ampleon_structured_sections_from_blocks(table_blocks: list[dict[str, Any]], full_text: str) -> dict[str, Any]:
    sections = build_generic_structured_sections_from_blocks(table_blocks, full_text)

    variants = parse_ampleon_variants(full_text)
    if variants:
        sections["variants"] = variants
        if not sections.get("package"):
            sections["package"] = variants[0].get("package")

    applications = extract_application_list(full_text, r"1\.3\s*Applications", [r"2\.\s*Pinning", r"Table\s*2\."])
    if applications:
        sections["application"] = applications

    rf_summary = parse_ampleon_rf_summary(full_text)
    for key, value in rf_summary.items():
        if key not in sections and is_plausible_rf_value(key, value):
            sections[key] = value

    return sections


def build_qorvo_structured_sections_from_blocks(table_blocks: list[dict[str, Any]], full_text: str) -> dict[str, Any]:
    return build_generic_structured_sections_from_blocks(table_blocks, full_text)


def get_vendor_profile(vendor: str) -> VendorExtractionProfile:
    vendor_key = (vendor or "").strip().lower()
    profiles: dict[str, VendorExtractionProfile] = {
        "nxp": VendorExtractionProfile(
            key="nxp",
            display_name="NXP",
            structured_section_builder=build_nxp_structured_sections_from_blocks,
            app_note_templates=["https://www.nxp.com/docs/en/application-note/{code}.pdf"],
            figure_keywords={
                "layout": DEFAULT_FIGURE_KEYWORDS["layout"] + ["production fixture", "component layout"],
                "package": DEFAULT_FIGURE_KEYWORDS["package"],
                "plot": DEFAULT_FIGURE_KEYWORDS["plot"],
            },
            notes=["NXP profile includes structured parsing for ordering variants, test circuits, impedance tables, and RF/DC characteristics."],
        ),
        "ampleon": VendorExtractionProfile(
            key="ampleon",
            display_name="Ampleon",
            structured_section_builder=build_ampleon_structured_sections_from_blocks,
            app_note_templates=["https://www.ampleon.com/documents/application-note/{code}.pdf"],
            figure_keywords=DEFAULT_FIGURE_KEYWORDS,
            notes=["Ampleon currently uses generic structured extraction with vendor-specific selectors from the seed catalog."],
        ),
        "qorvo": VendorExtractionProfile(
            key="qorvo",
            display_name="Qorvo",
            structured_section_builder=build_qorvo_structured_sections_from_blocks,
            app_note_templates=[],
            figure_keywords=DEFAULT_FIGURE_KEYWORDS,
            notes=["Qorvo currently uses generic structured extraction; extend this profile when a stable datasheet pattern is confirmed."],
        ),
        "guerrilla_rf": VendorExtractionProfile(
            key="guerrilla_rf",
            display_name="Guerrilla RF",
            structured_section_builder=build_generic_structured_sections_from_blocks,
            app_note_templates=[],
            figure_keywords=DEFAULT_FIGURE_KEYWORDS,
            notes=["Guerrilla RF currently uses the generic guarded profile; promote to a dedicated parser after the first stable GRF5219 extraction pass."],
        ),
    }
    return profiles.get(
        vendor_key,
        VendorExtractionProfile(
            key=vendor_key or "generic",
            display_name=VENDOR_DISPLAY_NAMES.get(vendor_key, (vendor_key or "Generic").capitalize()),
            structured_section_builder=build_generic_structured_sections_from_blocks,
            app_note_templates=[],
            figure_keywords=DEFAULT_FIGURE_KEYWORDS,
            notes=["Fallback generic profile; add a vendor-specific builder when datasheet structure diverges materially."],
        ),
    )


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
    effective_vendor = vendor or infer_vendor_key_from_url(seed.product_url)
    profile = get_vendor_profile(effective_vendor)
    part_number = seed.part_number or infer_part_number_from_url(seed.product_url)
    manufacturer = expected.get("manufacturer") or VENDOR_DISPLAY_NAMES.get(effective_vendor, effective_vendor.capitalize())
    if manufacturer.strip().lower() == effective_vendor:
        manufacturer = VENDOR_DISPLAY_NAMES.get(effective_vendor, manufacturer)
    technology = expected.get("technology", "") or ""

    crawl_text = crawl_result.get("markdown") or crawl_result.get("html") or ""
    fmin_guess, fmax_guess = infer_frequency_bounds(crawl_text)

    freq_min = expected.get("freq_min_mhz", fmin_guess if fmin_guess is not None else 0.0)
    freq_max = expected.get("freq_max_mhz", fmax_guess if fmax_guess is not None else 0.0)

    confidence = "high" if crawl_result.get("success") and fmin_guess is not None else "medium"
    if not crawl_result.get("success"):
        confidence = "low"

    # ── PDF datasheet extraction ─────────────────────────────────────────────
    pdf_params: dict[str, Any] = {}
    pdf_text_params: dict[str, Any] = {}
    pdf_url: str | None = None
    html_content = crawl_result.get("html", "") or ""
    markdown_content = crawl_result.get("markdown", "") or ""
    combined_content = "\n".join([markdown_content, html_content])
    extraction = seed.extraction or {}
    direct_pdf_url = extraction.get("datasheet_pdf_url")
    candidate_urls: list[str] = []
    if isinstance(direct_pdf_url, str) and direct_pdf_url.lower().startswith("http"):
        candidate_urls.append(direct_pdf_url)
    if crawl_result.get("success") and combined_content:
        for u in extract_datasheet_candidates(combined_content, seed.product_url):
            if u not in candidate_urls:
                candidate_urls.append(u)
    candidate_urls = rank_datasheet_candidates(candidate_urls, part_number, effective_vendor)

    pdf_bytes: bytes | None = None
    for cand in candidate_urls:
        print(f"[INFO] Trying datasheet candidate: {cand}", file=sys.stderr)
        pdf_try = download_pdf_bytes(cand)
        if pdf_try:
            pdf_url = cand
            pdf_bytes = pdf_try
            break

    pdf_parse_status = "not_attempted"
    full_pdf_text = ""
    pdf_page_count = 0
    table_blocks: list[dict[str, Any]] = []
    if pdf_bytes:
        pdf_parse_status = "pdf_downloaded"
        pdf_params = extract_params_from_pdf_bytes(pdf_bytes, seed.part_number)
        pdf_text_params = extract_params_from_pdf_text(pdf_bytes, seed.part_number)
        full_pdf_text, pdf_page_count = extract_pdf_full_text(pdf_bytes)
        table_blocks = extract_table_blocks_from_text(full_pdf_text)
        merged_count = len(set(list(pdf_params.keys()) + list(pdf_text_params.keys())))
        if merged_count > 0:
            pdf_parse_status = "params_extracted"
            print(
                f"[INFO] PDF extracted {merged_count} param(s) for {seed.part_number} "
                f"(table={len(pdf_params)}, text={len(pdf_text_params)})",
                file=sys.stderr,
            )
            confidence = "high"
        else:
            pdf_parse_status = "pdf_downloaded_no_params"
    elif candidate_urls:
        pdf_parse_status = "pdf_unreachable_from_candidates"
        print(f"[WARN] Datasheet candidates found but none returned PDF bytes for {part_number}", file=sys.stderr)

    combined_inference_text = "\n".join([combined_content, full_pdf_text])
    page_summary_fields = extract_page_summary_fields(combined_content)
    if not technology:
        technology = infer_technology(combined_inference_text)
    series = expected.get("series") or infer_series(part_number)
    typical_applications = extract_typical_applications(full_pdf_text)
    app_notes = extract_app_notes_from_page(combined_content, seed.product_url)
    for item in extract_app_notes_from_text(full_pdf_text, profile):
        if item not in app_notes:
            app_notes.append(item)
    structured_sections = profile.structured_section_builder(table_blocks, full_pdf_text)
    graphical_assets = extract_graphical_assets(effective_vendor, part_number, pdf_bytes, profile)
    if graphical_assets:
        structured_sections["graphical_data"] = graphical_assets
    artifact_paths = save_pdf_artifacts(effective_vendor, part_number, pdf_bytes, full_pdf_text, table_blocks)
    document_metadata = extract_document_metadata(full_pdf_text, pdf_page_count, pdf_url, part_number)
    pdf_summary_fields = extract_page_summary_fields(full_pdf_text)

    record = {
        "device_id": f"{effective_vendor}_{part_number}",
        "part_number": part_number,
        "manufacturer": manufacturer,
        "family": expected.get("family"),
        "series": series,
        "technology": technology,
        "freq_min_mhz": float(freq_min),
        "freq_max_mhz": float(freq_max),
        "datasheet_url": pdf_url or seed.product_url,
        "knowledge_source": "datasheet",
        "knowledge_confidence": confidence,
        "status": "active",
        "tags": ["crawl4ai-pilot", effective_vendor, technology.lower() if technology else "other"],
        "notes": "Auto-seeded by Crawl4AI pilot. Requires engineering review before production merge.",
        "extraction_blueprint": seed.extraction or {},
        "vendor_profile": {
            "key": profile.key,
            "display_name": profile.display_name,
            "strategy": profile.structured_section_builder.__name__,
            "notes": profile.notes,
        },
        "document_metadata": document_metadata,
        "app_notes": app_notes,
        "typical_applications": typical_applications,
        "extracted_table_blocks": table_blocks,
        "ingestion_provenance": {
            "crawled_at_utc": now_iso(),
            "crawl_success": crawl_result.get("success"),
            "http_status": crawl_result.get("status_code"),
            "source_domain": urlparse(seed.product_url).netloc,
            "source_title_hint": extract_title(crawl_result.get("markdown", "") or crawl_result.get("html", "")),
            "content_sha256": content_sha256(crawl_text),
            "crawl_error": crawl_result.get("error"),
            "selector_version": (seed.extraction or {}).get("selector_version"),
            "pdf_datasheet_url": pdf_url,
            "pdf_params_extracted": sorted(set(list(pdf_params.keys()) + list(pdf_text_params.keys()))),
            "pdf_parse_status": pdf_parse_status,
        },
    }
    record.update(artifact_paths)
    # Merge PDF table params first, then fill gaps from text fallback.
    for param, val in pdf_params.items():
        if param not in record and is_plausible_rf_value(param, val):
            record[param] = val
    for param, val in pdf_text_params.items():
        if param not in record and is_plausible_rf_value(param, val):
            record[param] = val

    for param, val in page_summary_fields.items():
        if param not in record or record.get(param) in (None, "", list(), 0):
            record[param] = val

    for param, val in pdf_summary_fields.items():
        if param not in record or record.get(param) in (None, "", list(), 0):
            record[param] = val

    # If PDF provides more accurate band limits, prefer them when seed expected was missing/zero.
    if record.get("freq_min_mhz", 0) <= 0 and "freq_min_mhz" in pdf_text_params:
        record["freq_min_mhz"] = float(pdf_text_params["freq_min_mhz"])
    if record.get("freq_max_mhz", 0) <= 0 and "freq_max_mhz" in pdf_text_params:
        record["freq_max_mhz"] = float(pdf_text_params["freq_max_mhz"])

    for key, value in structured_sections.items():
        if key in {"gain_db", "drain_eff_pct", "input_rl_db", "vdd_v"}:
            if is_plausible_rf_value(key, value):
                record[key] = value
            continue
        record[key] = value

    if typical_applications and not record.get("application"):
        record["application"] = typical_applications

    if isinstance(record.get("variants"), list):
        matching_variant = next(
            (
                item for item in record["variants"]
                if isinstance(item, dict)
                and isinstance(item.get("type_number"), str)
                and item.get("type_number", "").startswith(part_number)
            ),
            None,
        )
        if matching_variant and matching_variant.get("package"):
            record["package"] = matching_variant["package"]

    if not record.get("package"):
        package_name = extract_package_identifier(full_pdf_text, part_number)
        if package_name:
            record["package"] = package_name

    if pdf_parse_status in {"pdf_unreachable_from_candidates", "pdf_downloaded_no_params"}:
        record["notes"] = (
            "Auto-seeded by Crawl4AI pilot. Datasheet PDF could not be parsed fully; "
            "provide direct PDF URL or review manually before production merge."
        )
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

    http_status = provenance.get("http_status")
    if not isinstance(http_status, int) or http_status < 200 or http_status >= 400:
        errors.append("unexpected_http_status")

    # Some vendors prepend cookie-banner text as the first title line even when
    # full product content is crawled successfully. Treat this as blocking only
    # when confidence is not high.
    if is_suspicious_title(provenance.get("source_title_hint")) and record.get("knowledge_confidence") != "high":
        errors.append("suspicious_page_title")

    return errors


def append_records_to_vendor_file(vendor: str, records: list[dict[str, Any]]) -> Path:
    vendor_file = KB_ROOT / vendor / "devices.json"
    if not vendor_file.exists():
        vendor_file.parent.mkdir(parents=True, exist_ok=True)
        vendor_file.write_text("[]\n", encoding="utf-8")

    existing = json.loads(vendor_file.read_text(encoding="utf-8"))
    if not isinstance(existing, list):
        raise ValueError(f"Expected JSON array in {vendor_file}")

    replacement_map = {record.get("device_id"): record for record in records if record.get("device_id")}
    merged: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in existing:
        if not isinstance(item, dict):
            merged.append(item)
            continue
        device_id = item.get("device_id")
        if not device_id:
            merged.append(item)
            continue
        if device_id in replacement_map:
            merged.append(replacement_map[device_id])
            seen.add(device_id)
        else:
            merged.append(item)
    for device_id, record in replacement_map.items():
        if device_id not in seen:
            merged.append(record)

    vendor_file.write_text(json.dumps(merged, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    return vendor_file


async def run(args: argparse.Namespace) -> int:
    cfg = load_catalog(Path(args.config))
    runtime_ready, runtime_note = python_runtime_ready()

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
            extraction=item.get("extraction", {}),
        )
        for item in vendor_cfg.get("products", [])
    ]

    if args.max_products is not None:
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
            "python_version": sys.version.split()[0],
            "python_runtime_ready": runtime_ready,
            "runtime_note": runtime_note,
            "crawl4ai_available": HAS_CRAWL4AI,
            "discovery_url": vendor_cfg.get("discovery_url"),
            "max_products": len(seeds),
            "vendor_extraction_defaults": vendor_cfg.get("extraction_defaults", {}),
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
    parser.add_argument("--vendor", required=True)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument("--max-products", type=int, default=None,
        help="Optional cap on seeded products to crawl. Defaults to all seeded products for the vendor.")
    parser.add_argument("--apply", action="store_true", help="Append validated records to data/kb/<vendor>/devices.json")
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(run(parse_args())))
