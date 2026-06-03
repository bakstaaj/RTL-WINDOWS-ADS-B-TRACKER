# Dump1090 Windows ADS-B Decoder Dependency

This project uses the Windows-native Dump1090 implementation as the ADS-B decoder candidate/runtime:

- Upstream repository: https://github.com/gvanem/Dump1090
- Pinned tested commit: `4e28b9d8467f008c5725a69445fa0ec317e2250c`
- License: MIT, as declared by the upstream repository.
- Integration role: RTL-SDR 1090 MHz decoding and live HTTP aircraft JSON output.

## Why this decoder was selected

Native Windows testing on the GOLE2PRO established that:

- `readsb` did not compile natively under MSYS2 UCRT64 without larger POSIX portability work.
- Dump1090 builds as a Windows program using its MinGW-w64 toolchain path.
- It accepts numeric RTL-SDR device selection through `--device <index>`.
- It serves JSON through `/data/aircraft.json`.
- With the NooElec ADS-B dongle serial `00001090`, the tested working receive profile is:
  - sample rate: `2M`
  - tuner gain: `48.8` dB
  - frequency: `1090.0M`

## Required build accommodations

The reproducible build script performs these controlled accommodations:

1. Runs the upstream Python generator with MSYS2 `python3`.
2. Uses the upstream generator's supported `--mingw` mode so validation helpers compile with `gcc.exe` rather than `cl.exe`.
3. Applies `patches/0001-fix-http-json-size-parameter-calls.patch` to the pinned upstream checkout. The patch adds the optional `NULL` output-size argument at two stale HTTP JSON call sites in `src/net_io.c`.

The patch is preserved separately rather than vendoring or silently modifying third-party source.

## Runtime device rule

The application must not assume device index order. It must first run the project-owned device-role probe to resolve:

- `00001090` = ADS-B
- `00000162` = NOAA / Airband

Dump1090 is then launched with the numeric ADS-B session index returned by that probe.

## Runtime packaging note

`airport-codes.csv` is an upstream runtime dependency for HTTP/JSON startup. The build tool copies the upstream file beside the excluded `dump1090.exe` distribution output and the runtime validator supplies that copied path through `airports =`.
