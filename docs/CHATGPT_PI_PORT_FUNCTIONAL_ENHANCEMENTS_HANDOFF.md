# ChatGPT Handoff Summary: Port Windows Functional Enhancements Back to the Raspberry Pi Application

Date: 2026-06-05

This handoff summarizes the functional enhancements developed in the `RTL-Windows-ADS-B-Tracker` chat that should be considered for back-porting into the Raspberry Pi version of the ADS-B tracker application.

The Windows repo is:

```text
https://github.com/bakstaaj/RTL-WINDOWS-ADS-B-TRACKER
```

The related Pi repo/project context is the earlier Raspberry Pi ADS-B tracker work, generally referred to as:

```text
RTL-Pi-ADS-B-Tracker
```

## High-level outcome of the Windows chat

The Windows application reached a functional Release 1-style state with:

- Dual RTL-SDR role handling.
- ADS-B map UI.
- NOAA live audio and saved NOAA channel behavior.
- Airband manual listen and fast scanner search.
- Service release packaging.
- LAN web access and firewall setup.
- Improved trail-history display semantics.
- Generic, non-platform-specific UI text.
- Local callsign-prefix/operator fallback lookup.
- Local ICAO hex aircraft lookup database.
- Development validation with Python syntax checks and Node.js JavaScript syntax checks.

Many of these changes are portable to the Pi application because the browser UI behavior and backend API concepts are platform-independent.

## Recommended Pi port order

1. Port the map trail display behavior.
2. Remove Pi-specific wording from reusable UI messages.
3. Port the Airband UI defaults and layout changes.
4. Port the local operator-prefix fallback lookup.
5. Port the local ICAO hex aircraft database lookup.
6. Add importer scripts and runtime data management.
7. Add JavaScript syntax validation to the Pi development workflow.
8. Then evaluate whether any Windows-only service packaging ideas have Pi equivalents.

## Enhancement 1: Trail display mode — While Visible / Active

### Functional behavior

The Windows UI now defaults browser trail display to:

```text
While Visible / Active — save 4 hours
```

Behavior:

- A currently visible aircraft draws an active trail.
- When an aircraft is no longer in the active aircraft list, its displayed trail is removed from the map.
- The history itself is not deleted.
- History is retained for up to four hours.
- Clicking **Restore History** brings stored trails back into view.
- The default display stays clean while preserving historical recovery.

### Why port this to Pi

The Pi UI had useful restored/history trail behavior, but old trails could clutter the live map. The Windows change preserves the useful history while keeping the live view focused on active aircraft.

### Likely Pi files to update

Look for the Pi equivalent of:

```text
web/index.html
```

or any split JS file that contains:

- `aircraftTrailHistory`
- `aircraftTrailSegments`
- `renderStoredTrails`
- `removeTrailLayers`
- `loadPiTrailHistory`
- `erasePiTrailHistory`
- `trailRetention`
- map marker cleanup code

### Implementation notes

Add a display-mode concept separate from retention length:

```javascript
const TRAIL_DISPLAY_MODE_KEY = 'rtlAdsbTrailDisplayModeV1';
let aircraftTrailRetentionMinutes = 240;
let aircraftTrailDisplayMode = localStorage.getItem(TRAIL_DISPLAY_MODE_KEY) || 'active';
```

Add a selector option:

```html
<option value="active" selected>While Visible / Active — save 4 hours</option>
<option value="15">Show 15 minutes</option>
<option value="60">Show 1 hour</option>
<option value="240">Show 4 hours</option>
```

Add/remove per-aircraft trail layers:

```javascript
function removeTrailLayersForAircraft(key) {
  if (!aircraftMap) return;
  const segments = aircraftTrailSegments.get(key) || [];
  for (const segment of segments) aircraftMap.removeLayer(segment);
  aircraftTrailSegments.delete(key);
}
```

When active aircraft markers are removed because the aircraft disappeared from live data:

```javascript
if (aircraftTrailDisplayMode === 'active') removeTrailLayersForAircraft(key);
```

Modify `renderStoredTrails()` so it can render only active keys unless Restore History was requested:

```javascript
function renderStoredTrails(activeKeys = null) {
  removeTrailLayers();
  aircraftLastPositions.clear();
  pruneTrailHistory();

  if (aircraftTrailDisplayMode === 'active' && !activeKeys) return;

  const allowedKeys = activeKeys ? new Set(Array.from(activeKeys, key => String(key))) : null;
  for (const [key, points] of aircraftTrailHistory.entries()) {
    if (allowedKeys && !allowedKeys.has(String(key))) continue;
    // draw segments
  }
}
```

When Restore History is clicked, switch display mode to full history and show up to four hours:

```javascript
aircraftTrailDisplayMode = 'history';
aircraftTrailRetentionMinutes = 240;
renderStoredTrails(null);
```

## Enhancement 2: Remove platform-specific wording from UI messages

### Functional behavior

The green text to the right of the Restore History button previously referenced the underlying platform, such as “Pi history” or “Pi trail collector.” The Windows UI was changed to generic wording:

- `Restored history...`
- `Loaded history...`
- `Trail history unavailable...`
- `Display cleared. Trail history is still stored for up to 4 hours...`
- `Stored history erased...`

### Why port this to Pi

Even in the Pi app, user-facing messages do not need to expose implementation details. Generic wording makes the UI easier to share between Windows and Pi variants.

### Search terms

Search the Pi UI for:

```text
Pi trail
Pi history
Pi-stored
Raspberry
loadPiTrailHistory
erasePiTrailHistory
```

Function names can remain if desired, but user-visible strings should be made generic. For shared code, rename functions to platform-neutral names such as:

```javascript
loadTrailHistoryFromServer()
eraseTrailHistory()
```

## Enhancement 3: Airband scanner default squelch/activity threshold

### Functional behavior

Windows Airband scanner defaults were changed to:

```text
Default airband activity threshold: 1300 RMS
Default airband playback squelch: 1300 RMS
```

### Why port this to Pi

The Windows testing showed that the lower default threshold was too permissive for the desired scanner-start behavior. A default of `1300` was selected as the desired starting point.

### Likely Pi backend constants

Find the Pi equivalent of these Windows backend constants:

```python
DEFAULT_AIRBAND_ACTIVITY_RMS = 1300.0
DEFAULT_AIRBAND_PLAYBACK_SQUELCH_RMS = 1300.0
```

If existing runtime settings override defaults, update or migrate the existing `application_settings.json` values.

### Existing settings caveat

On already-installed systems, saved settings may override the new defaults. Provide a migration or document a one-time settings reset/update. The Windows one-time update pattern was:

```python
data["airband_activity_threshold_rms"] = 1300.0
data["airband_search_mode"] = "fast_spectrum"
data["airband_playback_squelch_rms"] = 1300.0
```

## Enhancement 4: Airband scanner search default and menu layout

### Functional behavior

Windows UI changes:

- Move **Apply Airband Tuning** directly under the **Scanner Search** dropdown.
- Set **Fast Spectrum Search** as the default scanner search mode.
- Keep traditional audio sample mode available.

### Why port this to Pi

The fast spectrum path became the preferred search workflow. Moving the apply button under Scanner Search makes the settings relationship clearer.

### Frontend implementation notes

In the Scanner Search dropdown:

```html
<option value="traditional">Traditional Audio Samples</option>
<option value="fast_spectrum" selected>Fast Spectrum Search — 120–130 MHz</option>
```

Default saved setting:

```javascript
byId("airbandSearchMode").value = settings.airband_search_mode || "fast_spectrum";
```

Backend default:

```python
DEFAULT_AIRBAND_SEARCH_MODE = "fast_spectrum"
```

## Enhancement 5: Local operator-prefix fallback lookup

### Functional behavior

The Windows UI previously relied heavily on online fallback lookup by the first three letters of the callsign. That missed many regional, cargo, and military/government operators.

A new local operator-prefix database was added:

```text
runtime/settings/operator_prefixes.json
```

Example records:

```json
{
  "SKW": {"icao":"SKW", "name":"SkyWest Airlines", "iata":"OO", "telephony":"SKYWEST", "category":"regional airline"},
  "RPA": {"icao":"RPA", "name":"Republic Airways", "iata":"YX", "telephony":"BRICKYARD", "category":"regional airline"},
  "EDV": {"icao":"EDV", "name":"Endeavor Air", "iata":"9E", "telephony":"ENDEAVOR", "category":"regional airline"},
  "RCH": {"icao":"RCH", "name":"United States Air Force Air Mobility Command", "telephony":"REACH", "category":"military"}
}
```

### Lookup order

The Windows operator lookup order became:

1. Exact aircraft/route lookup.
2. Local callsign prefix table.
3. ADSBDB airline endpoint fallback.

After the aircraft hex DB enhancement, the broader aircraft detail order became:

1. ADSBDB exact aircraft/route lookup.
2. Local ICAO hex aircraft database.
3. Local callsign-prefix/operator table.
4. ADSBDB callsign-prefix fallback.

### Backend endpoint to port

Add an endpoint similar to:

```text
GET /api/operator-prefixes.json
```

Backend behavior:

```python
operator_path = root / "runtime" / "settings" / "operator_prefixes.json"
if operator_path.is_file():
    send_json(json.loads(operator_path.read_text(encoding="utf-8")))
else:
    send_json({"version": "missing", "operators": {}})
```

### Frontend functions to port

Port these concepts:

```javascript
loadLocalOperatorPrefixLookup()
operatorMatchFromRecord(prefix, record, source)
fetchLocalOperatorByCallsignPrefix(callsign)
fetchAdsbdbOperatorByCallsignPrefix(callsign)
fetchOperatorByCallsignPrefix(callsign)
displayOperatorMatch(match)
```

Use the local table before the ADSBDB airline fallback.

### Pi data-management recommendation

For Pi, seed the JSON file under the app install directory or copy it to persistent runtime storage on first run. Keep it editable so local operators can be added without rebuilding.

## Enhancement 6: Local ICAO hex aircraft database lookup

### Functional behavior

The Windows app gained a local aircraft database keyed by six-character ICAO hex. This improves aircraft details when callsign prefixes are unavailable or ambiguous.

Generated file:

```text
runtime/settings/aircraft_hex_db.json
```

Importer:

```text
tools/import_aircraft_hex_db.py
```

Backend endpoint:

```text
GET /api/aircraft/hex?hex=<ICAO_HEX>
```

Example response shape:

```json
{
  "matched": true,
  "hex": "A1B2C3",
  "aircraft": {
    "hex": "A1B2C3",
    "registration": "N123AB",
    "type": "B738",
    "icao_type": "B738",
    "model": "Boeing 737-800",
    "description": "Boeing 737-800",
    "operator": "Example Operator",
    "registered_owner": "Example Operator",
    "owner_operator": "Example Operator",
    "source": "tar1090-db compact import"
  },
  "database": {
    "available": true,
    "record_count": 123456
  }
}
```

### Why port this to Pi

The Pi app can benefit even more than the Windows app because it may run continuously without needing internet access for every aircraft detail popup. A local hex DB provides offline enrichment and reduces dependency on third-party API availability.

### Backend class to port

Port the Windows `AircraftHexDatabase` concept:

```python
class AircraftHexDatabase:
    def __init__(self, path: Path) -> None: ...
    @staticmethod
    def normalize_hex(value: Any) -> str: ...
    def lookup(self, value: Any) -> dict[str, Any]: ...
```

Important behavior:

- Lazy-load JSON from disk.
- Cache by file modification time.
- Normalize ICAO hex to uppercase six-character value.
- Return structured `matched`, `hex`, `aircraft`, and `database` metadata.
- Avoid crashing the backend if the database is missing or malformed.

### Frontend functions to port

```javascript
async function fetchLocalAircraftByHex(rawHex) { ... }
function localAircraftOperatorName(aircraft) { ... }
function localAircraftRegistration(aircraft) { ... }
function localAircraftModelText(aircraft) { ... }
```

Integrate this into the aircraft detail popup before callsign-prefix fallback.

### Importer notes

The Windows importer was updated after the first attempt produced zero records. The corrected importer:

- Downloads `aircraft.csv.gz` from the tar1090-db CSV branch.
- Detects gzip vs plain CSV.
- Rejects accidental HTML downloads.
- Auto-detects comma, semicolon, tab, and pipe delimiters.
- Handles headered and some headerless CSV layouts.
- Normalizes likely column aliases for hex, registration, type, model, description, operator, manufacturer, year, and category.
- Prints a clear warning and preview lines if zero records are parsed.

For the Pi app, reuse the corrected importer rather than the original zero-record version.

### Storage warning

The generated JSON may be large. For the Pi app, consider one of these approaches:

1. Do not commit the generated DB. Commit only the importer and generate the DB on the Pi.
2. Package a compressed DB and expand during install.
3. Store a smaller regional subset if storage is limited.
4. Keep the full DB in persistent runtime data outside git.

## Enhancement 7: Aircraft detail display integration

### Functional behavior

The selected aircraft details panel now uses local data to fill:

- Registration.
- Manufacturer.
- Model/type.
- Operator/owner.
- Tail-number actions.

When local hex lookup succeeds but online photo lookup fails, the UI reports that local aircraft data was used rather than showing a generic total failure.

### Suggested detail status text

```text
Aircraft lookup complete using the local ICAO hex database.
```

When all lookup paths fail:

```text
No public aircraft, local aircraft, or route match was found for this target.
```

## Enhancement 8: LAN/browser binding and service/firewall behavior

### Functional behavior in Windows

The Windows service was changed to:

```text
--host 0.0.0.0 --port 8090
```

The installer creates a Windows Firewall allow rule:

```text
RTL ADS-B Tracker Web UI TCP 8090
```

### Pi relevance

The Pi app probably already listens on a LAN interface or is commonly accessed over the LAN. Still, check that:

- The backend bind host is configurable.
- Default bind host is appropriate for appliance use.
- Documentation clearly says how to access from another device.
- If a firewall is enabled on the Pi, document `ufw allow 8090/tcp` or equivalent.

Do not port Windows Firewall commands directly to the Pi.

## Enhancement 9: Windows Service packaging ideas with possible Pi equivalents

Windows-specific changes:

- PyInstaller backend bundle.
- WinSW service wrapper.
- `%ProgramData%\RTL ADS-B Tracker` runtime paths.
- Windows Firewall `netsh advfirewall` rule.

Pi equivalents might be:

- systemd unit file.
- `/opt/rtl-pi-adsb-tracker` or repo working directory for app files.
- `/var/lib/rtl-pi-adsb-tracker` for runtime data.
- `/var/log/rtl-pi-adsb-tracker` for logs.
- `ufw` or nftables documentation if needed.

This is mostly packaging/documentation, not functional UI logic.

## Enhancement 10: Development validation improvements

### Python syntax validation

Windows workflow used:

```bash
python3 -m py_compile \
  src/backend/rtl_windows_backend.py \
  src/backend/rtl_windows_pi_port_backend.py \
  src/backend/faa_airband_catalog.py \
  tools/import_aircraft_hex_db.py
```

For Pi, adapt to the Pi backend filenames.

### JavaScript syntax validation

Because the UI JavaScript is inline in `web/index.html`, Windows workflow extracted scripts into a temporary file and ran Node.js syntax checking:

```bash
python3 - <<'PY'
from pathlib import Path
import re

html = Path('web/index.html').read_text(encoding='utf-8')
Path('runtime/index_scripts_check.js').parent.mkdir(parents=True, exist_ok=True)
Path('runtime/index_scripts_check.js').write_text(
    '\n\n'.join(re.findall(r'<script>(.*?)</script>', html, flags=re.S)),
    encoding='utf-8'
)
PY

node --check runtime/index_scripts_check.js
rm -f runtime/index_scripts_check.js
```

For Pi, install Node.js or use an equivalent check in the development environment. Do not commit the generated `runtime/index_scripts_check.js` file.

## Enhancement 11: README and operational documentation

The Windows repo now needs a complete README covering:

- Hardware requirements.
- Dev environment setup.
- Build steps.
- Release packaging.
- Deployment.
- UI usage.
- Troubleshooting.
- Data-source attribution.

The Pi repo should receive a similar update once these enhancements are ported.

## Known Windows files touched during this chat

These are the Windows-side files involved in the enhancements and are useful references while porting:

```text
web/index.html
src/backend/rtl_windows_pi_port_backend.py
src/backend/rtl_windows_backend.py
tools/build_windows_service_release.sh
tools/import_aircraft_hex_db.py
runtime/settings/operator_prefixes.json
runtime/settings/aircraft_hex_db.json
docs/WINDOWS_SERVICE_RELEASE.md
README.md
```

Some files may be generated or runtime-local. Review `.gitignore` before committing large data files.

## Suggested Pi branch plan

```bash
cd ~/sdrdev/RTL-Pi-ADS-B-Tracker
git checkout main
git pull --ff-only

git checkout -b feature/windows-parity-trails-and-airband-ui
# port trail display, generic text, airband defaults/layout
# validate map and audio UI
# commit

git checkout -b feature/local-operator-and-aircraft-lookup
# port operator_prefixes.json, importer, backend endpoints, aircraft detail UI integration
# validate detail lookup with known callsigns/hex values
# commit
```

Keep trail/UI changes separate from local DB/enrichment changes if possible. That makes rollback and live testing easier.

## Validation checklist for Pi port

### Map/trails

- Live aircraft draw trails while active.
- Aircraft disappearing from active feed removes its visible trail.
- Restore History brings back stored trails.
- History remains limited to four hours.
- UI messages do not mention Pi/Raspberry unless intentionally describing system settings.

### Airband

- Default scanner search is Fast Spectrum Search.
- Default threshold/squelch is `1300 RMS`.
- Apply Airband Tuning appears under Scanner Search.
- Existing manual listen still works.
- Existing stop-listening control still works.

### Operator/aircraft lookup

- Known regional callsign prefixes resolve locally, such as `SKW`, `RPA`, `EDV`, `ENY`.
- Cargo prefixes such as `FDX` and `UPS` resolve locally.
- Military/government examples such as `RCH`, `SAM`, `PAT`, `CNV` resolve locally where present in the seed table.
- ICAO hex endpoint returns a record for a known hex in the imported database.
- Aircraft detail popup uses local hex DB data when online lookup misses.
- The UI falls back gracefully when no local DB exists.

### Runtime/data

- Missing `operator_prefixes.json` returns an empty table, not a crash.
- Missing `aircraft_hex_db.json` returns `matched: false`, not a crash.
- Large DB storage location is appropriate for the Pi filesystem.
- Importer handles zero-record cases with diagnostics.

## Final recommendation

Port the UI behavior first because it is low risk and immediately improves map readability. Then port the local operator-prefix lookup because it is small and editable. Finally port the ICAO hex DB because it is the largest data-management change and needs decisions about storage, update cadence, and whether the generated database belongs in git or runtime data only.
