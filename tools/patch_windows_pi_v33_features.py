#!/usr/bin/env python3
"""
Patch selected RTL-Pi ADS-B Tracker v3.3.0 functions into RTL-Windows-ADS-B-Tracker.

Run from MSYS2 UCRT64 inside the repo root:

    cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
    cp /c/Users/jim/Downloads/patch_windows_pi_v33_features.py tools/
    python3 tools/patch_windows_pi_v33_features.py

What this applies:
  1. Backend alias: /api/aircraft/local?hex=xxxxxx -> existing local aircraft hex DB lookup.
  2. Backend AirLabs lookup normalization: KAL032 retries as KAL32 after original.
  3. Backend route no-match classification for tail-number and private/charter prefixes.
  4. Browser helper functions for the same route-source wording.
  5. Browser active-trail cleanup when a live aircraft disappears, while keeping history data.
  6. Browser aircraft marker double-click hook that opens/selects the same aircraft detail record.
  7. Documentation notes for this Windows port checkpoint.

The patch is intentionally conservative and idempotent. It does not touch NOAA/Airband DSP paths.
"""
from __future__ import annotations

import argparse
import os
import py_compile
import re
import shutil
import subprocess
import sys
import textwrap
import time
from pathlib import Path

PATCH_ID = "RTP-PI-V33-WINDOWS-PORT"

BACKEND_INSERT = r'''

# RTP-PI-V33-WINDOWS-PORT BEGIN
# Compatibility helpers ported from the Raspberry Pi v3.3.0 route/identity behavior.
# These are attached as an AirLabsIntegration method override so the existing
# Windows backend remains otherwise unchanged.
_RTP_V33_PRIVATE_ROUTE_PREFIXES = {
    "KOW": "Baker Aviation / Rodeo",
    "LYM": "Key Lime Air",
    "LXJ": "Flexjet",
    "EJA": "NetJets",
    "XOJ": "XOJET",
    "FTH": "Mountain Aviation",
    "GAJ": "Wheels Up",
    "WUP": "Wheels Up",
    "JTL": "Jet Linx",
    "TWY": "Solairus Aviation",
    "PEG": "Pegasus Elite Aviation",
    "XSR": "Executive Flight Services",
}


def _rtp_v33_callsign_variants(callsign: str) -> list[str]:
    """Return the original ICAO callsign plus safe AirLabs retry variants."""
    cleaned = "".join(ch for ch in str(callsign or "").upper().strip() if ch.isalnum())
    variants: list[str] = []
    if cleaned:
        variants.append(cleaned)
    match = re.match(r"^([A-Z]{2,4})0+([1-9][0-9A-Z]*)$", cleaned)
    if match:
        normalized = match.group(1) + match.group(2)
        if normalized not in variants:
            variants.append(normalized)
    return variants


def _rtp_v33_is_tail_number_callsign(callsign: str) -> bool:
    value = "".join(ch for ch in str(callsign or "").upper().strip() if ch.isalnum() or ch == "-")
    compact = value.replace("-", "")
    if re.match(r"^N[1-9][0-9]{0,4}[A-Z]{0,2}$", compact):
        return True
    if re.match(r"^(C|CF|CG|G|D|F|I|EC|EI|OY|PH|HB|SE|LN|OH|OK|OM|SP|OE|VH|ZK|ZS)[A-Z]{3,5}$", compact):
        return True
    if re.match(r"^JA[0-9]{4}$", compact):
        return True
    if re.match(r"^HL[0-9]{4}$", compact):
        return True
    return False


def _rtp_v33_route_no_match_message(callsign: str, provider: str = "AirLabs") -> tuple[str, str | None, str | None]:
    value = "".join(ch for ch in str(callsign or "").upper().strip() if ch.isalnum() or ch == "-")
    compact = value.replace("-", "")
    if _rtp_v33_is_tail_number_callsign(value):
        return (
            f"Private/general aviation tail-number callsign - {value}; route not available from {provider}",
            "tail_number",
            None,
        )
    prefix = compact[:3]
    operator = _RTP_V33_PRIVATE_ROUTE_PREFIXES.get(prefix)
    if operator:
        return (
            f"Private/charter callsign - {operator}; route not available from {provider}",
            "private_charter",
            operator,
        )
    return (f"{provider} - no route match for {value or 'callsign'}", "no_match", None)


def _rtp_v33_airlabs_fetch_route(self, callsign: str, base: dict[str, Any], key: str) -> dict[str, Any]:
    query = urllib.parse.urlencode({"flight_icao": callsign, "api_key": key})
    request = urllib.request.Request(
        "https://airlabs.co/api/v9/flight?" + query,
        headers={"Accept": "application/json", "User-Agent": "RTL-Windows-ADS-B-Tracker/pi-port-v3.3"},
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")[:240]
        return {**base, "matched": False, "lookup_callsign": callsign, "message": f"AirLabs HTTP {exc.code}: {body}"}
    except Exception as exc:
        return {**base, "matched": False, "lookup_callsign": callsign, "message": f"AirLabs request failed: {exc}"}

    if isinstance(payload, dict) and payload.get("error"):
        error = payload["error"]
        message = error.get("message") if isinstance(error, dict) else str(error)
        return {**base, "matched": False, "lookup_callsign": callsign, "message": f"AirLabs error: {message}"}

    record = payload.get("response") if isinstance(payload, dict) and isinstance(payload.get("response"), dict) else payload
    if not isinstance(record, dict):
        return {**base, "matched": False, "lookup_callsign": callsign, "message": f"No route record returned for {callsign}."}

    fields = {
        "flight_icao": record.get("flight_icao") or callsign,
        "flight_iata": record.get("flight_iata"),
        "departure_iata": record.get("dep_iata"),
        "departure_icao": record.get("dep_icao"),
        "arrival_iata": record.get("arr_iata"),
        "arrival_icao": record.get("arr_icao"),
        "registration": record.get("reg_number"),
        "aircraft_icao": record.get("aircraft_icao"),
        "status": record.get("status"),
    }
    matched = any(fields[name] for name in ("departure_iata", "departure_icao", "arrival_iata", "arrival_icao"))
    return {
        **base,
        "matched": matched,
        **fields,
        "lookup_callsign": callsign,
        "cache_hit": False,
        "cache_age_seconds": 0,
        "cache_ttl_seconds": self.CACHE_TTL_SECONDS,
        "message": "Route fields returned." if matched else f"AirLabs returned no origin/destination for {callsign}.",
    }


def _rtp_v33_airlabs_lookup_route(self, flight: str) -> dict[str, Any]:
    status = self.status()
    key = self._api_key()
    base = {
        "provider": "AirLabs",
        "diagnostic_only": True,
        "configured": status["configured"],
        "key_hint": status["key_hint"],
    }
    if not key:
        return {**base, "matched": False, "message": "No readable AirLabs key was found in runtime/settings/airlabs_api.json."}

    callsign = self._clean_callsign(flight)
    if not callsign:
        return {**base, "matched": False, "message": "Provide a commercial flight ICAO callsign, for example UAL1234."}

    variants = _rtp_v33_callsign_variants(callsign)
    last_result: dict[str, Any] | None = None
    for variant in variants:
        cached = self._load_cached(variant)
        if cached is not None:
            cached.update({
                "requested_callsign": callsign,
                "lookup_callsign": variant,
                "matched_callsign": variant,
                "normalized_lookup_used": variant != callsign,
                "callsign_variants": variants,
            })
            return cached

        result = _rtp_v33_airlabs_fetch_route(self, variant, base, key)
        result.update({
            "requested_callsign": callsign,
            "lookup_callsign": variant,
            "normalized_lookup_used": variant != callsign,
            "callsign_variants": variants,
        })
        if result.get("matched"):
            result["matched_callsign"] = variant
            self._save_cached(variant, result)
            return result
        last_result = result

    message, classification, operator = _rtp_v33_route_no_match_message(callsign, "AirLabs")
    return {
        **base,
        "matched": False,
        "requested_callsign": callsign,
        "lookup_callsign": variants[-1] if variants else callsign,
        "normalized_lookup_used": len(variants) > 1,
        "callsign_variants": variants,
        "route_classification": classification,
        "classified_operator": operator,
        "message": message,
        "last_provider_message": (last_result or {}).get("message"),
    }


AirLabsIntegration.lookup_route = _rtp_v33_airlabs_lookup_route  # type: ignore[method-assign]
# RTP-PI-V33-WINDOWS-PORT END
'''

FRONTEND_INSERT = r'''
/* RTP-PI-V33-WINDOWS-PORT BEGIN */
const RTP_V33_PRIVATE_CALLSIGN_PREFIXES={KOW:"Baker Aviation / Rodeo",LYM:"Key Lime Air",LXJ:"Flexjet",EJA:"NetJets",XOJ:"XOJET",FTH:"Mountain Aviation",GAJ:"Wheels Up",WUP:"Wheels Up",JTL:"Jet Linx",TWY:"Solairus Aviation",PEG:"Pegasus Elite Aviation",XSR:"Executive Flight Services"};
function rtpV33CleanCallsign(value){return String(value||"").toUpperCase().trim().replace(/[^A-Z0-9-]/g,"");}
function rtpV33CompactCallsign(value){return rtpV33CleanCallsign(value).replace(/-/g,"");}
function rtpV33IsTailNumberCallsign(value){const v=rtpV33CleanCallsign(value),c=v.replace(/-/g,"");return /^N[1-9][0-9]{0,4}[A-Z]{0,2}$/.test(c)||/^(C|CF|CG|G|D|F|I|EC|EI|OY|PH|HB|SE|LN|OH|OK|OM|SP|OE|VH|ZK|ZS)[A-Z]{3,5}$/.test(c)||/^JA[0-9]{4}$/.test(c)||/^HL[0-9]{4}$/.test(c);}
function rtpV33NormalizedCallsignVariants(value){const c=rtpV33CompactCallsign(value),variants=[];if(c)variants.push(c);const m=c.match(/^([A-Z]{2,4})0+([1-9][0-9A-Z]*)$/);if(m){const n=m[1]+m[2];if(!variants.includes(n))variants.push(n);}return variants;}
function rtpV33RouteNoMatchSourceMessage(callsign,provider="AirLabs"){const v=rtpV33CleanCallsign(callsign),c=v.replace(/-/g,"");if(rtpV33IsTailNumberCallsign(v))return `Private/general aviation tail-number callsign - ${v}; route not available from ${provider}`;const operator=RTP_V33_PRIVATE_CALLSIGN_PREFIXES[c.slice(0,3)];if(operator)return `Private/charter callsign - ${operator}; route not available from ${provider}`;return `${provider} - no route match for ${v||"callsign"}`;}
if(typeof window!=="undefined"){window.rtpV33IsTailNumberCallsign=rtpV33IsTailNumberCallsign;window.rtpV33NormalizedCallsignVariants=rtpV33NormalizedCallsignVariants;window.rtpV33RouteNoMatchSourceMessage=rtpV33RouteNoMatchSourceMessage;if(!window.isTailNumberCallsign)window.isTailNumberCallsign=rtpV33IsTailNumberCallsign;if(!window.routeNoMatchSourceMessage)window.routeNoMatchSourceMessage=rtpV33RouteNoMatchSourceMessage;if(!window.normalizedIcaoCallsignVariants)window.normalizedIcaoCallsignVariants=rtpV33NormalizedCallsignVariants;}
/* RTP-PI-V33-WINDOWS-PORT END */
'''

DOC_TEXT = """# Windows Port of Raspberry Pi v3.3.0 Functional Enhancements

This checkpoint ports the safest browser/backend compatibility pieces from the Raspberry Pi v3.3.0 functional baseline into the Windows application without disturbing the validated Windows ADS-B, NOAA, and Airband receiver workflows.

## Implemented in this patch

- Added `/api/aircraft/local?hex=<ICAO_HEX>` as a Pi-compatible alias for the Windows local aircraft hex database lookup.
- Added AirLabs callsign normalization so airline-style callsigns with leading zeros can retry with the numeric zero padding removed. Example: `KAL032` first checks `KAL032`, then `KAL32`.
- Added backend and browser route-source classification for private/charter prefixes and registration-style tail-number callsigns.
- Added active trail cleanup when an aircraft leaves the current live aircraft set. The visible live trail layer is removed, but retained browser/backend history is not erased.
- Added a map marker double-click handler that selects the aircraft and calls the existing aircraft details popup function when present.

## Validation checklist

1. Start the Windows Pi-port backend and open the UI.
2. Confirm the browser console has no JavaScript syntax errors.
3. Double-click an aircraft icon on the map. The aircraft should be selected, and the full detail popup should open when the detail-popup function exists in the current UI build.
4. Watch an aircraft leave range. Its marker and active visible trail should disappear; Restore History should still be able to recover retained trail history.
5. Test route lookup examples:
   - `KAL032` should include lookup variants `KAL032`, `KAL32`.
   - `KOW523` should classify as Baker Aviation / Rodeo when no AirLabs route exists.
   - `LYM3583` should classify as Key Lime Air when no AirLabs route exists.
   - `N653JC` should classify as private/general aviation tail-number route unavailable.
6. Test local aircraft metadata lookup:
   - `/api/aircraft/local?hex=AE68F2`
   - `/api/aircraft/hex?hex=AE68F2`
   Both should return the same local hex DB response shape.

## Notes

The patch is intentionally idempotent and tagged with `RTP-PI-V33-WINDOWS-PORT`. Re-running the patch should not duplicate the inserted helper blocks.
"""

README_SECTION = """

## Raspberry Pi v3.3.0 parity checkpoint

This Windows build includes selected parity behavior from the Raspberry Pi v3.3.0 tracker baseline:

- Split `web/index.html`, `web/app.css`, and `web/app.js` assets.
- Local tar1090-style aircraft hex metadata lookup through `/api/aircraft/hex` and Pi-compatible `/api/aircraft/local`.
- AirLabs route lookup normalization for ICAO callsigns with leading zero flight numbers.
- Clearer route-source messages for private/charter/operator callsigns and registration-style tail-number callsigns.
- Active map trail cleanup when aircraft leave the live aircraft set, while preserving stored history for Restore History.
- Aircraft marker double-click selection/detail access using the same aircraft record used by the aircraft list.

See `docs/WINDOWS_PI_V33_PORT_IMPLEMENTATION.md` for validation examples.
"""


def backup_file(path: Path) -> None:
    if not path.exists():
        return
    stamp = time.strftime("%Y%m%d_%H%M%S")
    backup = path.with_suffix(path.suffix + f".bak_{stamp}")
    shutil.copy2(path, backup)


def replace_once(text: str, old: str, new: str, label: str, required: bool = True) -> tuple[str, bool]:
    if old in text:
        return text.replace(old, new, 1), True
    if required:
        raise RuntimeError(f"Could not find patch target for {label}.")
    return text, False


def patch_backend(repo: Path) -> list[str]:
    backend = repo / "src" / "backend" / "rtl_windows_pi_port_backend.py"
    if not backend.exists():
        raise FileNotFoundError(f"Missing backend file: {backend}")
    text = backend.read_text(encoding="utf-8")
    changes: list[str] = []

    if PATCH_ID not in text:
        if "class AircraftHexDatabase" not in text:
            raise RuntimeError("Could not find class AircraftHexDatabase insertion point.")
        backup_file(backend)
        text = text.replace("class AircraftHexDatabase", BACKEND_INSERT + "\nclass AircraftHexDatabase", 1)
        changes.append("Added AirLabs normalization and route classification monkey-patch.")
    else:
        changes.append("AirLabs normalization/classification block already present.")

    # Add Pi-compatible local aircraft endpoint alias if only the Windows endpoint exists.
    if 'request.path in ("/api/aircraft/hex", "/api/aircraft/local")' not in text:
        patterns = [
            ('request.path == "/api/aircraft/hex"', 'request.path in ("/api/aircraft/hex", "/api/aircraft/local")'),
            ("request.path == '/api/aircraft/hex'", "request.path in ('/api/aircraft/hex', '/api/aircraft/local')"),
        ]
        for old, new in patterns:
            if old in text:
                backup_file(backend)
                text = text.replace(old, new, 1)
                changes.append("Added /api/aircraft/local alias to existing aircraft hex lookup.")
                break
        else:
            changes.append("No /api/aircraft/hex endpoint pattern found; alias not changed.")
    else:
        changes.append("/api/aircraft/local alias already present.")

    backend.write_text(text, encoding="utf-8", newline="\n")
    try:
        py_compile.compile(str(backend), doraise=True)
        changes.append("Backend Python syntax check passed.")
    except Exception as exc:
        changes.append(f"WARNING: backend syntax check failed: {exc}")
    return changes


def patch_frontend(repo: Path) -> list[str]:
    app = repo / "web" / "app.js"
    if not app.exists():
        raise FileNotFoundError(f"Missing browser file: {app}")
    text = app.read_text(encoding="utf-8")
    changes: list[str] = []
    original = text

    if PATCH_ID not in text:
        if text.startswith('"use strict";'):
            text = text.replace('"use strict";', '"use strict";\n' + FRONTEND_INSERT, 1)
        elif text.startswith("'use strict';"):
            text = text.replace("'use strict';", "'use strict';\n" + FRONTEND_INSERT, 1)
        else:
            text = FRONTEND_INSERT + "\n" + text
        changes.append("Added browser callsign normalization and route-source classification helpers.")
    else:
        changes.append("Browser classification helper block already present.")

    # Disable Leaflet double-click zoom so aircraft icon double-click is not consumed by map zoom.
    if "doubleClickZoom.disable" not in text:
        text, changed = replace_once(
            text,
            'state.map=L.map("map").setView([state.receiver.latitude,state.receiver.longitude],9);',
            'state.map=L.map("map").setView([state.receiver.latitude,state.receiver.longitude],9);if(state.map.doubleClickZoom)state.map.doubleClickZoom.disable();',
            "disable Leaflet double-click zoom",
            required=False,
        )
        if changed:
            changes.append("Disabled Leaflet double-click zoom for aircraft map interactions.")
        else:
            changes.append("Could not locate minified initMap pattern for double-click zoom disable.")

    # Add double-click handler to the current marker creation chain.
    if "rtpV33OpenAircraftDetailsFromMap" not in text:
        helper = 'function rtpV33OpenAircraftDetailsFromMap(hex,a,event){if(event&&typeof L!=="undefined"&&L.DomEvent)L.DomEvent.stop(event);selectAircraft(hex);const latest=(state.rows&&state.rows.get(hex))||a;if(typeof window.openAircraftDetails==="function")window.openAircraftDetails(latest);else if(typeof window.showAircraftDetails==="function")window.showAircraftDetails(latest);else if(typeof renderSelected==="function")renderSelected();}'
        insert_after = "function updateAircraft(data){"
        if insert_after in text:
            text = text.replace(insert_after, helper + insert_after, 1)
            changes.append("Added reusable marker double-click detail opener.")
        else:
            text += "\n" + helper + "\n"
            changes.append("Added marker double-click helper at end of app.js; update hook still needs manual review.")

    double_click_new = '.addTo(state.map).on("click",()=>selectAircraft(hex)).on("dblclick",event=>rtpV33OpenAircraftDetailsFromMap(hex,a,event));state.markers.set(hex,m);'
    if double_click_new not in text:
        candidates = [
            '.addTo(state.map).on("click",()=>selectAircraft(hex));state.markers.set(hex,m);',
            '.addTo(state.map).on(\'click\',()=>selectAircraft(hex));state.markers.set(hex,m);',
        ]
        for old in candidates:
            if old in text:
                text = text.replace(old, double_click_new, 1)
                changes.append("Attached double-click handler to aircraft markers.")
                break
        else:
            changes.append("Could not locate marker creation chain; double-click hook may require manual integration.")
    else:
        changes.append("Marker double-click handler already present.")

    # Remove active visible trail layers when aircraft disappear from live set; preserve state.trails history storage.
    cleanup_new = 'if(!active.has(hex)){m.remove();state.markers.delete(hex);const layer=state.trailLayers.get(hex);if(layer){layer.clearLayers();layer.remove();state.trailLayers.delete(hex);}}'
    if cleanup_new not in text:
        cleanup_patterns = [
            'if(!active.has(hex)){m.remove();state.markers.delete(hex);}',
            'if (!active.has(hex)) {m.remove();state.markers.delete(hex);}',
        ]
        for old in cleanup_patterns:
            if old in text:
                text = text.replace(old, cleanup_new, 1)
                changes.append("Added active visible trail cleanup when aircraft leave live range.")
                break
        else:
            changes.append("Could not locate stale-marker cleanup block; trail cleanup may require manual integration.")
    else:
        changes.append("Active visible trail cleanup already present.")

    if text != original:
        backup_file(app)
        app.write_text(text, encoding="utf-8", newline="\n")
    return changes


def patch_docs(repo: Path) -> list[str]:
    changes: list[str] = []
    docs_dir = repo / "docs"
    docs_dir.mkdir(exist_ok=True)
    doc_path = docs_dir / "WINDOWS_PI_V33_PORT_IMPLEMENTATION.md"
    if not doc_path.exists() or PATCH_ID not in doc_path.read_text(encoding="utf-8", errors="ignore"):
        doc_path.write_text(f"<!-- {PATCH_ID} -->\n\n" + DOC_TEXT, encoding="utf-8", newline="\n")
        changes.append(f"Wrote {doc_path.relative_to(repo)}.")
    else:
        changes.append(f"{doc_path.relative_to(repo)} already present.")

    readme = repo / "README.md"
    if readme.exists():
        text = readme.read_text(encoding="utf-8")
        if "Raspberry Pi v3.3.0 parity checkpoint" not in text:
            backup_file(readme)
            readme.write_text(text.rstrip() + "\n" + README_SECTION + "\n", encoding="utf-8", newline="\n")
            changes.append("Appended README parity checkpoint section.")
        else:
            changes.append("README parity checkpoint section already present.")
    return changes


def run_optional_checks(repo: Path) -> list[str]:
    checks: list[str] = []
    if shutil.which("node") and (repo / "web" / "app.js").exists():
        result = subprocess.run(["node", "--check", "web/app.js"], cwd=repo, text=True, capture_output=True)
        if result.returncode == 0:
            checks.append("node --check web/app.js passed.")
        else:
            checks.append("WARNING: node --check web/app.js failed:\n" + (result.stderr or result.stdout))
    else:
        checks.append("node not found; skipped JavaScript syntax check.")
    return checks


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply Pi v3.3.0 parity patch to RTL-Windows-ADS-B-Tracker")
    parser.add_argument("repo", nargs="?", default=".", help="Path to RTL-Windows-ADS-B-Tracker repo root; default current directory")
    parser.add_argument("--skip-checks", action="store_true", help="Skip optional node syntax checks")
    args = parser.parse_args()

    repo = Path(args.repo).expanduser().resolve()
    if not (repo / "web").is_dir() or not (repo / "src" / "backend").is_dir():
        print(f"ERROR: {repo} does not look like the RTL-Windows-ADS-B-Tracker repo root.", file=sys.stderr)
        return 2

    print(f"Applying {PATCH_ID} in {repo}")
    all_changes: list[str] = []
    all_changes.extend(patch_backend(repo))
    all_changes.extend(patch_frontend(repo))
    all_changes.extend(patch_docs(repo))
    if not args.skip_checks:
        all_changes.extend(run_optional_checks(repo))

    print("\nPatch results:")
    for change in all_changes:
        print(f"  - {change}")

    print("\nNext commands:")
    print("  git diff -- src/backend/rtl_windows_pi_port_backend.py web/app.js README.md docs/WINDOWS_PI_V33_PORT_IMPLEMENTATION.md")
    print("  python3 -m py_compile src/backend/rtl_windows_pi_port_backend.py")
    print("  node --check web/app.js")
    print("  ./tools/restart_pi_port_service.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
