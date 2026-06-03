# RTL-Windows-ADS-B-Tracker

A clean Windows-native dual RTL-SDR aircraft tracking and VHF audio application for a Windows 11 GOLE2PRO computer with two NooElec NESDR Nano 3 receivers.

This is a new implementation informed by the verified behavior of the earlier Raspberry Pi `RTL-Pi-ADS-B-Tracker` project. It is not a patch or fork of the Pi application's source tree.

## Fixed receiver roles

| Role | RTL-SDR serial | Intended operation |
|---|---:|---|
| ADS-B | `00001090` | Continuous 1090 MHz aircraft reception/decoding |
| NOAA / Airband | `00000162` | NOAA Weather Radio NFM and civil-airband AM |

## Verified Windows platform baseline

Verified on 2026-06-03:

- MSYS2 UCRT64 development environment in `~/sdrdev`.
- GCC, CMake, Ninja, Make, pkg-config and Python available.
- Docker CLI installed.
- MSYS2 UCRT64 `rtl-sdr` package installed with native tools and development library.
- Both Nano 3 receivers read successfully by EEPROM serial number.
- Both receivers captured I/Q concurrently after serials were resolved sequentially to current numeric indexes.

See `docs/VERIFIED_WINDOWS_BASELINE.md` and `docs/ARCHITECTURE.md`.

## Current stage

This repository starts with the Windows project scaffold and reproducible Docker Windows-x64 cross-toolchain verification. No application functionality is implemented yet.

## Initial developer workflow

From MSYS2 UCRT64:

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/build_windows_x64_image.sh
./tools/test_windows_x64_cross_toolchain.sh
git status --short
```

The Docker step is used for reproducible Windows-x64 builds. Live RTL-SDR device testing remains native on Windows.

## Native device-role probe

The first native Windows component resolves the two RTL-SDR roles sequentially by EEPROM serial number and can open/read both receiver handles in a single process:

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/build_native_device_probe.sh
./tools/test_native_device_probe.sh
```

This implements the verified startup rule needed to avoid concurrent serial-discovery conflicts on the dual RTL-SDR Windows host.

## Windows ADS-B decoder integration

The validated Windows ADS-B decoder candidate is `gvanem/Dump1090`. It is built reproducibly from a pinned upstream commit into ignored build/output directories and is started only after the native device-role probe resolves the ADS-B receiver serial to its current session index.

Verified receiver profile on the GOLE2PRO with NooElec serial `00001090`:

```text
Frequency:   1090.0 MHz
Sample rate: 2.0 MS/s
Tuner gain:  48.8 dB
JSON API:    /data/aircraft.json
```

Build and verify:

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/build_dump1090_windows.sh
./tools/test_dump1090_adsb_json.sh
```

See `docs/ADSB_DECODER_INTEGRATION.md` and `external/dump1090/README.md` for upstream attribution and the documented compatibility patch.

## Initial backend API

The application-owned backend now wraps the validated Windows Dump1090 decoder behind stable API endpoints. It performs the required sequential device-role resolution before launching ADS-B decoding and proxies live aircraft JSON for the future web interface.

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/run_backend_dev.sh
```

Development API base URL:

```text
http://127.0.0.1:8090
```

See `docs/BACKEND_API.md` for endpoints and validation instructions.

## Live map UI baseline

The application backend now serves the initial browser map interface:

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/run_backend_dev.sh
```

Then browse to `http://127.0.0.1:8090/`. The UI displays live markers and browser-session trails using application API endpoints rather than directly coupling the browser to Dump1090. See `docs/WEB_MAP_UI.md`.
