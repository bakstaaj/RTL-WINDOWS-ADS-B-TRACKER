# RTL-Windows-ADS-B-Tracker

A Windows-native dual RTL-SDR aircraft tracking and VHF audio application. The project runs a local ADS-B tracker, browser map UI, NOAA Weather Radio listener, civil airband listener/scanner, aircraft enrichment lookups, and optional Windows Service packaging for unattended startup.

This application was developed as a Windows port and enhancement path for the earlier Raspberry Pi ADS-B tracker work. It is not a direct source-code fork of the Pi project; it uses the same operational ideas with a Windows-focused device, service, and packaging model.

## Core features

- Continuous ADS-B tracking on one RTL-SDR receiver.
- NOAA Weather Radio NFM live listening, capture, saved-channel reuse, and forced rescan workflow.
- Civil aviation AM airband manual listening and scanner workflow.
- Fast spectrum airband search mode.
- FAA NASR airband catalog import and distance-ranked frequency list.
- Browser map with live aircraft, receiver rings, selected-aircraft details, and altitude-colored trails.
- Trail display mode that defaults to **While Visible / Active** while preserving up to four hours of recoverable history.
- Restore History and Clear/Erase History controls.
- Aircraft enrichment from ADSBDB, local callsign-prefix fallback data, and a local ICAO hex aircraft database.
- Windows Service release package using WinSW and a PyInstaller backend bundle.
- LAN web access on TCP port `8090` with an install-time Windows Firewall rule.

## Hardware requirements

### Required

| Item | Notes |
|---|---|
| Windows 10 or Windows 11 computer | Verified development target is Windows 11 with MSYS2 UCRT64. A small always-on PC works well. |
| Two RTL-SDR receivers | The reference hardware is two NooElec NESDR Nano 3 dongles. Other RTL2832U/R820T2-compatible receivers may work. |
| ADS-B antenna | Tuned for 1090 MHz. Outdoor or window placement improves range. |
| VHF antenna | Suitable for NOAA Weather Radio around 162 MHz and civil airband 118–137 MHz. |
| RTL-SDR Windows driver support | Zadig/libusb-compatible driver setup is typically required for native RTL-SDR tools. |

### Reference receiver serial assignments

The application assumes fixed receiver roles by RTL-SDR EEPROM serial number:

| Role | Serial | Purpose |
|---|---:|---|
| ADS-B | `00001090` | Continuous 1090 MHz ADS-B reception and decoding. |
| NOAA / Airband | `00000162` | NOAA Weather Radio NFM and civil airband AM audio. |

Set or verify serials with standard RTL-SDR tools before relying on service startup. The project resolves serials sequentially before opening long-running decoder/audio processes to avoid Windows dual-device enumeration conflicts.

## Software architecture

```text
RTL-Windows-ADS-B-Tracker/
├── src/
│   ├── backend/
│   │   ├── rtl_windows_pi_port_backend.py   # Main Windows backend used by the UI/service package
│   │   ├── rtl_windows_backend.py           # Earlier/alternate backend entry point
│   │   └── faa_airband_catalog.py           # FAA FRQ.csv importer and catalog normalizer
│   └── native/
│       └── rtl_dual_device_probe.c          # Native serial-to-role RTL-SDR probe
├── web/
│   ├── index.html                           # Browser UI and inline application JavaScript
│   ├── app.css
│   └── app.js
├── tools/
│   ├── build_native_device_probe.sh
│   ├── build_dump1090_windows.sh
│   ├── import_faa_airband_catalog.sh
│   ├── import_aircraft_hex_db.py
│   ├── build_windows_service_release.sh
│   ├── run_pi_port_dev.sh
│   └── test_*.sh
├── docs/
│   └── Detailed feature and validation notes
├── runtime/
│   └── settings/, logs/, build/             # Local/generated data; usually not committed except selected seed data
└── dist/
    └── native-windows/, third_party/        # Built native runtime outputs
```

The backend owns the radio processes and exposes stable local HTTP APIs. The browser UI talks to the backend, not directly to Dump1090 or `rtl_fm`.

## Development environment

Use **MSYS2 UCRT64** as the main build/test shell.

### Install MSYS2 packages

Open **MSYS2 UCRT64** and run:

```bash
pacman -Syu
```

If MSYS2 asks you to close the terminal, close it, reopen **MSYS2 UCRT64**, then run:

```bash
pacman -Syu
pacman -S --needed \
  git \
  base-devel \
  mingw-w64-ucrt-x86_64-toolchain \
  mingw-w64-ucrt-x86_64-cmake \
  mingw-w64-ucrt-x86_64-ninja \
  mingw-w64-ucrt-x86_64-pkgconf \
  mingw-w64-ucrt-x86_64-rtl-sdr \
  mingw-w64-ucrt-x86_64-nodejs \
  curl \
  zip \
  unzip \
  make
```

Verify:

```bash
which gcc
which cmake
which ninja
which rtl_fm
which rtl_power
which node
node --version
python3 --version
```

### Install native Windows Python

The Windows Service release builder uses PyInstaller and needs a real Windows Python installation. MSYS2 Python is useful for development scripts, but a python.org or Windows-native Python is preferred for release packaging.

Install Python 3.12 from PowerShell, Command Prompt, or MSYS2:

```bash
cmd.exe /c winget install -e --id Python.Python.3.12
```

Close and reopen **MSYS2 UCRT64** after installation.

The release builder accepts a Windows Python from one of these sources:

- `py -3`
- `py.exe -3`
- Windows `python.exe`
- Common python.org install paths under `C:\Users\<user>\AppData\Local\Programs\Python\...`

It should not use `C:/msys64/ucrt64/bin/python.exe` for the final PyInstaller service bundle.

### Optional tools

- Docker Desktop: used by older cross-toolchain verification scripts.
- GitHub CLI: useful for publishing release assets, but not required for normal git push.

```bash
cmd.exe /c winget install -e --id GitHub.cli
```

## Clone and initial setup

```bash
cd ~/sdrdev
git clone git@github.com:bakstaaj/RTL-WINDOWS-ADS-B-TRACKER.git RTL-Windows-ADS-B-Tracker
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
```

If using an SSH alias, use your configured remote instead.

Check the local tree:

```bash
git status --short
git branch --show-current
```

## Build instructions

### 1. Build the native RTL-SDR device probe

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/build_native_device_probe.sh
./tools/test_native_device_probe.sh
```

The probe should find both serials and confirm that both receivers can be opened by resolved session index.

### 2. Build the Windows Dump1090 runtime

```bash
./tools/build_dump1090_windows.sh
./tools/test_dump1090_adsb_json.sh
```

The Dump1090 runtime is staged under:

```text
dist/third_party/dump1090/
```

### 3. Import the FAA airband catalog

Download the FAA NASR Frequency Data CSV ZIP that contains `FRQ.csv`, then import it:

```bash
./tools/import_faa_airband_catalog.sh /c/Users/jim/Downloads/FAA_NASR_YYYY-MM-DD_FRQ_CSV.zip
```

Output:

```text
runtime/settings/faa_airband_catalog.json
```

This catalog is used to build the distance-ranked airband channel list and to validate manual airband tuning selections.

### 4. Import the local aircraft ICAO hex database

The local ICAO hex database improves aircraft details when the online aircraft/route lookup or callsign-prefix lookup misses.

```bash
python3 tools/import_aircraft_hex_db.py
```

Output:

```text
runtime/settings/aircraft_hex_db.json
```

If this file is very large, consider whether you want it committed to git or generated locally during release preparation. The service release builder can package the local DB if it exists.

### 5. Validate Python and JavaScript

```bash
python3 -m py_compile \
  src/backend/rtl_windows_backend.py \
  src/backend/rtl_windows_pi_port_backend.py \
  src/backend/faa_airband_catalog.py \
  tools/import_aircraft_hex_db.py
```

Extract inline scripts from the UI and syntax-check them with Node.js:

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

`node --check` prints nothing when the JavaScript syntax is valid.

## Development run

Run the backend directly from MSYS2 UCRT64:

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/run_pi_port_dev.sh
```

Open:

```text
http://127.0.0.1:8090/
```

For LAN testing, run the backend with host `0.0.0.0` or use the packaged Windows Service release, which is configured to listen on all local interfaces.

## Windows Service release build

The release builder packages:

- PyInstaller backend executable.
- Browser UI.
- Native RTL-SDR probe.
- Dump1090 runtime.
- `rtl_fm.exe`, `rtl_power.exe`, and required DLLs.
- FAA airband catalog seed data.
- Optional local aircraft hex DB seed data if present.
- WinSW service wrapper.
- Install, uninstall, restart, stop, status, and open-browser helper scripts.

Build a release ZIP:

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/build_windows_service_release.sh v1.0.3
```

Expected output:

```text
C:\Users\jim\Downloads\RTL-ADS-B-Tracker-Windows-Service-v1.0.3.zip
```

The script should report the Windows Python it selected. If it reports MSYS2 Python for the PyInstaller build, fix Python detection before publishing the release.

## Deployment instructions

### Install as a Windows Service

1. Copy the release ZIP to the target Windows machine.
2. Extract it into a stable folder, for example:

   ```text
   C:\RTL-ADS-B-Tracker\
   ```

3. Open **Command Prompt as Administrator**.
4. Change into the extracted release folder.
5. Run:

   ```cmd
   install_service.cmd
   ```

The installer:

- Creates `%ProgramData%\RTL ADS-B Tracker\runtime`.
- Creates `%ProgramData%\RTL ADS-B Tracker\logs`.
- Seeds runtime settings/catalog files when they do not already exist.
- Installs and starts the `RTLADSBTracker` Windows Service.
- Adds a Windows Firewall inbound allow rule for TCP `8090`.

### Service helper scripts

Run these from an Administrator Command Prompt in the extracted release folder:

```cmd
status_service.cmd
restart_service.cmd
stop_service.cmd
uninstall_service.cmd
open_tracker.cmd
```

### Web access

On the Windows host:

```text
http://127.0.0.1:8090/
```

From another device on the same trusted LAN:

```text
http://<windows-host-ip>:8090/
```

Verify LAN listening:

```cmd
netstat -ano | findstr :8090
netsh advfirewall firewall show rule name="RTL ADS-B Tracker Web UI TCP 8090"
```

You want the service to listen on `0.0.0.0:8090` for LAN access.

Only expose the service on a trusted network. The UI is intended for local/LAN operational use, not direct public internet exposure.

### Uninstall

From an Administrator Command Prompt in the extracted release folder:

```cmd
uninstall_service.cmd
```

The uninstall script stops and removes the service and removes the firewall rule. ProgramData settings and logs are intentionally retained unless removed manually.

## User interface guide

### Receiver Status

The receiver status panel shows:

- ADS-B receiver role and serial.
- Audio receiver role and serial.
- Receiver location.
- Decoder status.
- Audio status.
- Message/aircraft counts.

Set the receiver label, latitude, and longitude before relying on distance-ranked airband results.

### Map

The map displays live ADS-B aircraft markers, altitude-colored trails, receiver rings, and selected-aircraft details.

Trail behavior:

- Default: **While Visible / Active**.
- When an aircraft leaves active range, its visible trail is removed from the map.
- Trail history is still stored for up to four hours.
- **Restore History** brings the stored trail history back into view.
- **Clear Display** clears the browser display but keeps restorable history.
- **Erase History** removes stored history.

Trail colors are altitude-based:

| Altitude | Trail color intent |
|---:|---|
| `< 5,001 ft` | Bright green |
| `< 10,001 ft` | Dark green |
| `< 20,001 ft` | Light blue |
| `< 30,001 ft` | Dark blue |
| `< 40,001 ft` | Dark yellow |
| `>= 40,001 ft` | Bright red |

### Aircraft details and enrichment

Click an aircraft to open details. The UI attempts enrichment in this order:

1. Exact aircraft/route lookup where available.
2. Local ICAO hex aircraft database.
3. Local callsign-prefix/operator table.
4. ADSBDB callsign-prefix fallback.

The local operator-prefix table is editable and is useful for regional carriers, cargo operators, and military/government prefixes that online fallback sources may miss.

### NOAA Weather Radio

NOAA features use the second RTL-SDR receiver.

Typical controls include:

- Scan/select NOAA Weather Radio channel.
- Listen live.
- Stop listening.
- Capture/download WAV audio.
- Save and reuse the working NOAA channel.
- Force rescan when the receiver location changes or when reception changes.

The saved NOAA channel avoids unnecessary rescans after a known-good channel is found.

### Airband

Airband features use civil VHF AM channels from the imported FAA catalog.

Typical controls include:

- Nearby FAA airband channels sorted by distance.
- Scanner Search dropdown.
- Default search mode: **Fast Spectrum Search**.
- Apply Airband Tuning button under Scanner Search.
- Default scanner squelch/activity threshold: `1300 RMS`.
- Manual Listen from a selected channel.
- Stop Listening.
- Survey Scan.
- Multi-pass review.
- Candidate-level review.
- Cross-pass and segment-variation review.
- CSV export of scan evidence.

Survey Scan is evidence/review oriented. It ranks and marks channels for operator review; it should not be treated as a guaranteed voice-activity detector.

## Runtime settings and generated files

Development runtime files live under:

```text
runtime/settings/
runtime/logs/
runtime/build/
```

Installed service runtime files live under:

```text
%ProgramData%\RTL ADS-B Tracker\runtime
%ProgramData%\RTL ADS-B Tracker\logs
```

Important runtime settings include:

| File | Purpose |
|---|---|
| `application_settings.json` | Receiver location, tuning defaults, saved NOAA channel, airband settings. |
| `faa_airband_catalog.json` | Imported FAA channel catalog. |
| `operator_prefixes.json` | Local three-letter callsign prefix/operator fallback table. |
| `aircraft_hex_db.json` | Local ICAO hex aircraft details database. |
| `aircraft_trails_history.json` | Four-hour server-side trail history cache. |
| `airlabs_api.json` | Optional AirLabs API configuration if used. |

Do not commit logs, captures, build outputs, or generated JavaScript check files.

## Git workflow

Recommended workflow:

```bash
git checkout main
git pull --ff-only
git checkout -b feature/<short-feature-name>

# make changes
python3 -m py_compile src/backend/*.py tools/import_aircraft_hex_db.py
bash -n tools/build_windows_service_release.sh
node --check runtime/index_scripts_check.js  # after extracting inline scripts

# run one meaningful live validation for tuner/audio/backend changes
git status --short
git add <source files only>
git commit -m "Describe the validated change"

git checkout main
git merge --no-ff feature/<short-feature-name> -m "Merge <feature summary>"
git push origin main
```

For release tags:

```bash
git tag -a v1.0.3 -m "Release 1.0.3 - local ICAO hex aircraft lookup"
git push origin v1.0.3
```

## Troubleshooting

### `gh: command not found`

GitHub CLI is optional. Install it if you want to create GitHub Releases from the command line:

```bash
cmd.exe /c winget install -e --id GitHub.cli
```

Or create the release manually through the GitHub web UI.

### `node: command not found`

Install Node.js in MSYS2 UCRT64:

```bash
pacman -S mingw-w64-ucrt-x86_64-nodejs
```

### Release builder selects MSYS2 Python

Install Python for Windows and reopen MSYS2 UCRT64:

```bash
cmd.exe /c winget install -e --id Python.Python.3.12
```

The release builder should use a Windows Python, not `C:/msys64/ucrt64/bin/python.exe`.

### Release builder cannot find `rtl_fm.exe` or `rtl_power.exe`

Install the MSYS2 UCRT64 RTL-SDR package and confirm the tools are in PATH:

```bash
pacman -S mingw-w64-ucrt-x86_64-rtl-sdr
which rtl_fm
which rtl_power
```

### Web UI is reachable locally but not from another device

Check that the service is bound to all interfaces and that the firewall rule exists:

```cmd
netstat -ano | findstr :8090
netsh advfirewall firewall show rule name="RTL ADS-B Tracker Web UI TCP 8090"
```

Also confirm the Windows network profile and any third-party firewall rules.

### FAA airband list is empty

Confirm that receiver latitude/longitude are configured and the FAA catalog was imported:

```bash
ls -lh runtime/settings/faa_airband_catalog.json
```

### Aircraft hex DB imported zero records

Use the updated importer and review its diagnostic output. It should parse the downloaded CSV/GZIP into a large nonzero record count:

```bash
python3 tools/import_aircraft_hex_db.py
```

## Attribution

This project integrates or uses data/tools from several upstream sources:

- RTL-SDR/librtlsdr tools for receiver access.
- Dump1090 Windows runtime for ADS-B decoding.
- WinSW for Windows Service hosting.
- FAA NASR Frequency Data for airband channel catalog generation.
- ADSBDB for aircraft/route/photo/operator enrichment where available.
- tar1090/readsb-compatible aircraft database data for local ICAO hex enrichment where imported.

Confirm upstream licenses and attribution requirements when publishing binary release packages.


## Raspberry Pi v3.3.0 parity checkpoint

This Windows build includes selected parity behavior from the Raspberry Pi v3.3.0 tracker baseline:

- Split `web/index.html`, `web/app.css`, and `web/app.js` assets.
- Local tar1090-style aircraft hex metadata lookup through `/api/aircraft/hex` and Pi-compatible `/api/aircraft/local`.
- AirLabs route lookup normalization for ICAO callsigns with leading zero flight numbers.
- Clearer route-source messages for private/charter/operator callsigns and registration-style tail-number callsigns.
- Active map trail cleanup when aircraft leave the live aircraft set, while preserving stored history for Restore History.
- Aircraft marker double-click selection/detail access using the same aircraft record used by the aircraft list.

See `docs/WINDOWS_PI_V33_PORT_IMPLEMENTATION.md` for validation examples.

