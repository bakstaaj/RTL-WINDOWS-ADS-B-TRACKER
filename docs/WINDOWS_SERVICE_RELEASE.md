# Windows Service Release Packaging

The Windows release runs **RTL ADS-B Tracker** as a Windows Service rather than a shell-background process.

## Architecture

- `RTLADSBTrackerService.exe` is the bundled service executable based on WinSW v2.12.0 (MIT license).
- `RTLADSBTrackerService.xml` registers the service with Windows Service Control Manager and launches the backend.
- `app\backend\RTLADSBTrackerBackend.exe` is built by PyInstaller from `src/backend/rtl_windows_pi_port_backend.py`.
- `web`, `dist`, and `bin` contain the browser UI and required native SDR/ADS-B runtime files.
- Settings and logs are written beneath `%ProgramData%\RTL ADS-B Tracker`, not inside the release folder.

WinSW is used because it is specifically designed to wrap and manage an executable as a Windows service, supporting install, start, stop, restart, status and recovery behavior.

## Build prerequisite

Run from MSYS2 UCRT64 on the validated Windows machine. The build invokes native Windows CPython through `py -3` to create the bundled Windows backend executable. End users do not need Python installed.

The validated runtime must already be present locally:

- `dist\native-windows\rtl_dual_device_probe.exe`
- `dist\third_party\dump1090\dump1090.exe`
- `dist\third_party\dump1090\airport-codes.csv`
- `rtl_fm.exe` and `rtl_power.exe` in PATH
- `runtime\settings\faa_airband_catalog.json`

## Build

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/build_windows_service_release.sh v0.1.0-rc1
```

The ZIP is written to `C:\Users\jim\Downloads`.

## Install on Windows

Extract the ZIP to a permanent location such as:

```text
C:\Program Files\RTL ADS-B Tracker
```

From an **Administrator Command Prompt**, run:

```cmd
install_service.cmd
```

Then browse to:

```text
http://127.0.0.1:8090/
```

The release also contains `status_service.cmd`, `restart_service.cmd`, `stop_service.cmd`, `uninstall_service.cmd`, and `open_tracker.cmd`.

## Runtime data and security

The ZIP does not package user settings, AirLabs credentials, route caches, trail history, PID files, logs or audio recordings. The FAA airband catalog is seeded as non-private operational reference data on installation. Runtime changes remain beneath `%ProgramData%\RTL ADS-B Tracker\runtime`.

## Third-party component

WinSW is distributed under the MIT License. Its license and attribution are included in the release under `notices`.
