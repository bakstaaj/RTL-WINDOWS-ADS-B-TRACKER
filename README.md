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
