#!/usr/bin/env python3
# Import and query official FAA NASR FRQ airband records.
# Generated catalog JSON is runtime data and is not intended for Git storage.

from __future__ import annotations

import argparse
import csv
import io
import json
import math
from pathlib import Path
from typing import Any
from zipfile import ZipFile

LOW_AIRBAND_MHZ = 118.0
HIGH_AIRBAND_MHZ = 136.975
DEFAULT_RADIUS_MILES = 100.0
DEFAULT_LIMIT = 50


def _category(frequency_use: str, facility_type: str) -> str:
    use = frequency_use.upper()
    facility = facility_type.upper()
    for term, category in (
        ("ATIS", "ATIS"),
        ("AWOS", "Weather"),
        ("ASOS", "Weather"),
        ("CTAF", "CTAF"),
        ("UNICOM", "UNICOM"),
        ("GROUND", "Ground"),
        ("GND", "Ground"),
        ("CLEARANCE", "Clearance"),
        ("DELIVERY", "Clearance"),
        ("TOWER", "Tower"),
        ("TWR", "Tower"),
        ("APPROACH", "Approach"),
        ("APCH", "Approach"),
        ("DEPARTURE", "Departure"),
        ("DEP", "Departure"),
        ("RCO", "RCO"),
    ):
        if term in use or term in facility:
            return category
    return "Other"


def _haversine_miles(latitude_a: float, longitude_a: float, latitude_b: float, longitude_b: float) -> float:
    radius = 3958.7613
    phi_a, phi_b = math.radians(latitude_a), math.radians(latitude_b)
    dphi = math.radians(latitude_b - latitude_a)
    dlambda = math.radians(longitude_b - longitude_a)
    value = math.sin(dphi / 2) ** 2 + math.cos(phi_a) * math.cos(phi_b) * math.sin(dlambda / 2) ** 2
    return radius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value))


def import_frq_zip(frq_zip: Path, output_path: Path) -> dict[str, Any]:
    with ZipFile(frq_zip) as archive:
        member = next((name for name in archive.namelist() if Path(name).name.upper() == "FRQ.CSV"), None)
        if member is None:
            raise ValueError(f"FRQ.csv was not found in {frq_zip}.")
        text = archive.read(member).decode("utf-8-sig", errors="replace")
    rows = csv.DictReader(io.StringIO(text, newline=""))
    channels: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    effective_dates: set[str] = set()
    skipped = 0
    for row in rows:
        try:
            frequency_mhz = float(row.get("FREQ", "").strip())
            latitude = float(row.get("LAT_DECIMAL", "").strip())
            longitude = float(row.get("LONG_DECIMAL", "").strip())
        except ValueError:
            skipped += 1
            continue
        if not LOW_AIRBAND_MHZ <= frequency_mhz <= HIGH_AIRBAND_MHZ:
            continue
        if row.get("SERVICED_COUNTRY", "").strip().upper() != "US":
            continue
        serviced_facility = row.get("SERVICED_FACILITY", "").strip()
        use = row.get("FREQ_USE", "").strip()
        key = (serviced_facility, round(frequency_mhz, 6), use, round(latitude, 7), round(longitude, 7))
        if key in seen:
            continue
        seen.add(key)
        effective_date = row.get("EFF_DATE", "").strip()
        if effective_date:
            effective_dates.add(effective_date)
        channels.append(
            {
                "frequency_mhz": round(frequency_mhz, 6),
                "frequency_hz": int(round(frequency_mhz * 1_000_000)),
                "frequency_use": use,
                "category": _category(use, row.get("FACILITY_TYPE", "")),
                "facility": row.get("FACILITY", "").strip(),
                "facility_type": row.get("FACILITY_TYPE", "").strip(),
                "serviced_facility": serviced_facility,
                "serviced_facility_name": row.get("SERVICED_FAC_NAME", "").strip(),
                "serviced_site_type": row.get("SERVICED_SITE_TYPE", "").strip(),
                "tower_or_comm_call": row.get("TOWER_OR_COMM_CALL", "").strip(),
                "primary_approach_radio_call": row.get("PRIMARY_APPROACH_RADIO_CALL", "").strip(),
                "city": row.get("SERVICED_CITY", "").strip(),
                "state": row.get("SERVICED_STATE", "").strip(),
                "latitude": latitude,
                "longitude": longitude,
                "remark": row.get("REMARK", "").strip(),
            }
        )
    channels.sort(key=lambda item: (item["state"], item["city"], item["frequency_mhz"], item["frequency_use"]))
    data = {
        "schema_version": 1,
        "source": "FAA NASR Frequency Data FRQ.csv",
        "source_archive": frq_zip.name,
        "effective_dates": sorted(effective_dates),
        "airband_low_mhz": LOW_AIRBAND_MHZ,
        "airband_high_mhz": HIGH_AIRBAND_MHZ,
        "channel_count": len(channels),
        "skipped_invalid_rows": skipped,
        "channels": channels,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(output_path.suffix + ".tmp")
    temporary_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8", newline="\n")
    temporary_path.replace(output_path)
    return data


class AirbandCatalog:
    def __init__(self, catalog_path: Path) -> None:
        self.catalog_path = catalog_path
        self._modified_ns: int | None = None
        self._data: dict[str, Any] | None = None

    def _load(self) -> dict[str, Any] | None:
        if not self.catalog_path.exists():
            self._modified_ns = None
            self._data = None
            return None
        modified_ns = self.catalog_path.stat().st_mtime_ns
        if self._data is None or modified_ns != self._modified_ns:
            self._data = json.loads(self.catalog_path.read_text(encoding="utf-8"))
            self._modified_ns = modified_ns
        return self._data

    def find_channel(self, frequency_hz: int, serviced_facility: str = "", frequency_use: str = "") -> dict[str, Any] | None:
        data = self._load()
        if data is None:
            return None
        requested_facility = serviced_facility.strip().upper()
        requested_use = frequency_use.strip().upper()
        matches: list[dict[str, Any]] = []
        for channel in data.get("channels", []):
            if int(channel.get("frequency_hz", 0)) != int(frequency_hz):
                continue
            if requested_facility and str(channel.get("serviced_facility", "")).upper() != requested_facility:
                continue
            if requested_use and str(channel.get("frequency_use", "")).upper() != requested_use:
                continue
            matches.append(dict(channel))
        if not matches:
            return None
        matches.sort(key=lambda item: (item.get("serviced_facility", ""), item.get("frequency_use", "")))
        return matches[0]

    def query(self, receiver_location: dict[str, Any], radius_miles: float = DEFAULT_RADIUS_MILES, limit: int = DEFAULT_LIMIT) -> dict[str, Any]:
        data = self._load()
        radius = max(1.0, min(float(radius_miles), 500.0))
        bounded_limit = max(1, min(int(limit), 200))
        if data is None:
            return {
                "ok": True,
                "catalog_available": False,
                "receiver_location": receiver_location,
                "radius_miles": radius,
                "channels": [],
                "message": "Run tools/import_faa_airband_catalog.sh to generate the FAA airband catalog.",
            }
        latitude = float(receiver_location["latitude"])
        longitude = float(receiver_location["longitude"])
        ranked: list[dict[str, Any]] = []
        for channel in data.get("channels", []):
            distance = _haversine_miles(latitude, longitude, float(channel["latitude"]), float(channel["longitude"]))
            if distance <= radius:
                enriched = dict(channel)
                enriched["distance_miles"] = round(distance, 1)
                ranked.append(enriched)
        ranked.sort(key=lambda item: (item["distance_miles"], item["frequency_mhz"], item["frequency_use"]))
        return {
            "ok": True,
            "catalog_available": True,
            "source": data.get("source"),
            "effective_dates": data.get("effective_dates", []),
            "total_catalog_channels": data.get("channel_count", 0),
            "receiver_location": receiver_location,
            "radius_miles": radius,
            "matching_channel_count": len(ranked),
            "channels": ranked[:bounded_limit],
        }


def main() -> int:
    parser = argparse.ArgumentParser(description="Import official FAA NASR FRQ CSV ZIP as application airband catalog.")
    parser.add_argument("--frq-zip", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    data = import_frq_zip(args.frq_zip, args.output)
    print(json.dumps({
        "ok": True,
        "output": str(args.output),
        "source_archive": data["source_archive"],
        "effective_dates": data["effective_dates"],
        "channel_count": data["channel_count"],
        "skipped_invalid_rows": data["skipped_invalid_rows"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
