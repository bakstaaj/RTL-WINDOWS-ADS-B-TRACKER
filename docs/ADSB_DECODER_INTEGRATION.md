# ADS-B Decoder Integration Baseline

## Selected feasibility candidate

The validated Windows-native ADS-B decoder candidate is **gvanem/Dump1090**, pinned for repeatability at:

`4e28b9d8467f008c5725a69445fa0ec317e2250c`

It is kept as a third-party dependency and is not copied into the application source tree. Reproducible build tooling checks out the pinned commit into ignored `build/` output, applies the documented compatibility patch, and produces an executable in ignored `dist/` output.

## Validated platform observations

| Test | Result |
|---|---|
| Dedicated ADS-B receiver | Serial `00001090` |
| Decoder device argument | Numeric index obtained from `rtl_dual_device_probe --json` |
| JSON endpoint | `/data/aircraft.json` |
| Successful receive sample rate | `2M` |
| Successful receive tuner gain | `48.8` dB |
| Competing 2.4M profiles | Received only a small number of messages in the same feasibility sequence |

## Device startup sequence

1. Enumerate RTL-SDR devices sequentially through the application-owned native probe.
2. Resolve serial `00001090` to the current ADS-B numeric device index.
3. Start Dump1090 with `--device <resolved_index>`.
4. Use the audio receiver, serial `00000162`, independently for NOAA or Airband operations.

## Third-party build accommodations

The Windows/MSYS2 build requires:

- `PYTHON=python3` because the upstream MinGW Makefile defaults to the Windows Python launcher command `py -3`.
- The official upstream generator `--mingw` option so generated validation utilities use GCC instead of Visual C++.
- A minimal tracked patch to two HTTP JSON call sites that were missing the newer optional output-size parameter.

## Validation command

From MSYS2 UCRT64:

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/build_dump1090_windows.sh
./tools/test_dump1090_adsb_json.sh
```

No decoder build artifacts, receiver captures, test JSON, or runtime configuration files are committed.

## Required runtime data file

The decoder distribution must include upstream `airport-codes.csv` beside the built `dump1090.exe`, or explicitly point the runtime configuration to the copied file using the `airports =` key. Without this file, Dump1090 exits before exposing `/data/aircraft.json`.
