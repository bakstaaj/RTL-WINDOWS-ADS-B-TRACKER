#!/usr/bin/env python3
"""Import a compact local ICAO hex aircraft database for RTL ADS-B Tracker.

Default source:
  https://github.com/wiedehopf/tar1090-db/raw/refs/heads/csv/aircraft.csv.gz

The output is a compact JSON map:
  runtime/settings/aircraft_hex_db.json

The importer is deliberately tolerant of CSV column-name changes.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import io
import json
import re
import sys
import time
import urllib.request
from pathlib import Path
from typing import Any

DEFAULT_URL = "https://github.com/wiedehopf/tar1090-db/raw/refs/heads/csv/aircraft.csv.gz"
FALLBACK_URLS = [
    DEFAULT_URL,
    "https://github.com/wiedehopf/tar1090-db/raw/csv/aircraft.csv.gz",
    "https://raw.githubusercontent.com/wiedehopf/tar1090-db/csv/aircraft.csv.gz",
]

HEX_RE = re.compile(r"^[0-9A-F]{6}$")

ALIASES = {
    "hex": ("icao", "icao24", "hex", "hexid", "mode_s", "modes", "mode_s_code", "mode_scode"),
    "registration": ("registration", "reg", "regid", "tail", "tail_number", "n_number"),
    "type": ("type", "typecode", "icao_type", "icao_aircraft_type"),
    "model": ("model", "mdl", "aircraft_model"),
    "description": ("desc", "description", "ldesc", "long_description", "aircraft_description"),
    "operator": ("operator", "ownop", "own_op", "owner", "registered_owner", "owner_operator"),
    "manufacturer": ("manufacturer", "mfr", "make"),
    "year": ("year", "built", "build_year"),
    "category": ("category", "cat"),
}

def normalize_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", str(value or "").strip().lower())

ALIAS_KEYS = {
    field: {normalize_key(alias) for alias in aliases}
    for field, aliases in ALIASES.items()
}

def clean(value: Any) -> str:
    return str(value or "").strip()

def detect_dialect(text: str) -> csv.Dialect:
    sample_lines = [line for line in text.splitlines()[:80] if line.strip()]
    sample = "\n".join(sample_lines[:40])
    try:
        return csv.Sniffer().sniff(sample, delimiters=",;\t|")
    except Exception:
        class FallbackDialect(csv.excel):
            delimiter = ","
        return FallbackDialect

def looks_like_html(text: str) -> bool:
    probe = text.lstrip()[:250].lower()
    return probe.startswith("<!doctype html") or probe.startswith("<html") or "<title>" in probe

def normalize_hex(value: Any) -> str:
    text = re.sub(r"[^0-9A-Fa-f]", "", str(value or "")).upper()
    return text if HEX_RE.match(text) else ""

def pick(row: dict[str, Any], field: str) -> str:
    aliases = ALIAS_KEYS[field]
    for key, value in row.items():
        if normalize_key(key) in aliases:
            selected = clean(value)
            if selected:
                return selected
    return ""

def download(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "RTL-Windows-ADS-B-Tracker aircraft DB importer",
            "Accept": "*/*",
        },
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()

def decode_blob(blob: bytes) -> str:
    if blob[:2] == b"\x1f\x8b":
        blob = gzip.decompress(blob)
    return blob.decode("utf-8-sig", errors="replace")

def has_header(first_row: list[str]) -> bool:
    normalized = {normalize_key(item) for item in first_row}
    all_aliases = set().union(*ALIAS_KEYS.values())
    return bool(normalized & all_aliases)

def record_from_dict(row: dict[str, Any]) -> tuple[str, dict[str, Any]] | None:
    hex_code = normalize_hex(pick(row, "hex"))
    if not hex_code:
        return None

    record: dict[str, Any] = {
        "hex": hex_code,
        "source": "tar1090-db compact import",
    }

    for field in ("registration", "type", "model", "description", "operator", "manufacturer", "year", "category"):
        value = pick(row, field)
        if value:
            record[field] = value

    # Browser compatibility aliases.
    if record.get("operator"):
        record["registered_owner"] = record["operator"]
        record["owner_operator"] = record["operator"]
    if record.get("type"):
        record["icao_type"] = record["type"]

    return hex_code, record

def record_from_position(row: list[str]) -> tuple[str, dict[str, Any]] | None:
    # Fallback for headerless CSV variants. Find the first six-hex field,
    # then map the following fields conservatively.
    fields = [clean(value) for value in row]
    if not fields:
        return None

    hex_index = -1
    hex_code = ""
    for index, field in enumerate(fields[:4]):
        candidate = normalize_hex(field)
        if candidate:
            hex_index = index
            hex_code = candidate
            break

    if not hex_code:
        return None

    tail = fields[hex_index + 1] if len(fields) > hex_index + 1 else ""
    type_code = fields[hex_index + 2] if len(fields) > hex_index + 2 else ""
    description = fields[hex_index + 3] if len(fields) > hex_index + 3 else ""
    operator = fields[hex_index + 4] if len(fields) > hex_index + 4 else ""
    year = fields[hex_index + 5] if len(fields) > hex_index + 5 else ""

    record: dict[str, Any] = {
        "hex": hex_code,
        "source": "tar1090-db compact import",
    }

    if tail:
        record["registration"] = tail
    if type_code:
        record["type"] = type_code
        record["icao_type"] = type_code
    if description:
        record["description"] = description
        record["model"] = description
    if operator:
        record["operator"] = operator
        record["registered_owner"] = operator
        record["owner_operator"] = operator
    if year:
        record["year"] = year

    return hex_code, record

def parse_aircraft_csv(text: str) -> tuple[dict[str, dict[str, Any]], list[str], bool]:
    if looks_like_html(text):
        raise ValueError("Downloaded file appears to be HTML, not aircraft CSV data. Check the source URL.")

    dialect = detect_dialect(text)
    sample_reader = csv.reader(io.StringIO(text), dialect=dialect)
    first: list[str] | None = None
    for row in sample_reader:
        if row and any(clean(item) for item in row):
            first = row
            break

    if not first:
        return {}, [], False

    header_mode = has_header(first)
    records: dict[str, dict[str, Any]] = {}

    if header_mode:
        reader = csv.DictReader(io.StringIO(text), dialect=dialect)
        header = list(reader.fieldnames or [])
        for row in reader:
            parsed = record_from_dict(row)
            if parsed:
                hex_code, record = parsed
                records[hex_code] = record
        return records, header, True

    reader = csv.reader(io.StringIO(text), dialect=dialect)
    for row in reader:
        parsed = record_from_position(row)
        if parsed:
            hex_code, record = parsed
            records[hex_code] = record

    return records, [], False

def main() -> int:
    parser = argparse.ArgumentParser(description="Import compact aircraft ICAO hex database.")
    parser.add_argument(
        "--url",
        default=DEFAULT_URL,
        help="CSV or CSV.GZ URL. Default is tar1090-db aircraft.csv.gz.",
    )
    parser.add_argument(
        "--output",
        default="runtime/settings/aircraft_hex_db.json",
        help="Output JSON path.",
    )
    parser.add_argument(
        "--input",
        help="Optional local aircraft.csv or aircraft.csv.gz file instead of downloading.",
    )
    args = parser.parse_args()

    source_url = args.url
    if args.input:
        source_label = str(Path(args.input))
        blob = Path(args.input).read_bytes()
    else:
        source_label = source_url
        last_error: Exception | None = None
        blob = b""
        urls = [source_url] + [url for url in FALLBACK_URLS if url != source_url]
        for url in urls:
            try:
                print(f"Downloading aircraft database: {url}")
                blob = download(url)
                source_label = url
                break
            except Exception as exc:
                last_error = exc
                print(f"  failed: {exc}", file=sys.stderr)
        if not blob:
            raise SystemExit(f"Unable to download aircraft database: {last_error}")

    text = decode_blob(blob)
    records, header, header_mode = parse_aircraft_csv(text)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": "tar1090-db aircraft.csv.gz",
        "source_url": source_label,
        "downloaded_utc": int(time.time()),
        "record_count": len(records),
        "header_detected": header_mode,
        "header": header[:40],
        "aircraft": dict(sorted(records.items())),
    }
    output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"Wrote {len(records):,} aircraft records to {output}")
    if header:
        print("Detected columns:", ", ".join(header[:16]))
    if not records:
        preview_lines = [line for line in text.splitlines()[:8] if line.strip()]
        print("WARNING: parsed zero records. First non-empty input lines:", file=sys.stderr)
        for line in preview_lines[:5]:
            print(line[:240], file=sys.stderr)
        return 2
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
