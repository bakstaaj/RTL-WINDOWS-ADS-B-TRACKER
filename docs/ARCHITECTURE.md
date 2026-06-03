# Architecture Baseline

## Design objective

Provide the map-first aircraft tracking and second-receiver audio workflows previously proven on Raspberry Pi, rebuilt cleanly for a Windows 11 dual-RTL-SDR host.

## Planned runtime components

| Component | Responsibility |
|---|---|
| Device manager | Sequentially enumerate RTL-SDR serial numbers and assign stable receiver roles. |
| ADS-B decoder worker | Permanently reserve the `00001090` receiver for 1090 MHz aircraft data. |
| Audio worker | Reserve `00000162` for mutually exclusive NOAA NFM or Airband AM operations. |
| Backend API | Coordinate workers, configuration, streaming, aircraft/trail data and diagnostics. |
| Web UI | Map-first interface with active aircraft, trails, receiver rings and audio controls. |
| Runtime settings | Local settings outside Git, including receiver location and optional API configuration. |

## Startup sequence

```text
Application start
  -> enumerate RTL devices once, sequentially
  -> map serial 00001090 to current ADS-B device index
  -> map serial 00000162 to current audio device index
  -> launch ADS-B worker first using mapped index
  -> launch optional NOAA/Airband operations using mapped audio index
```

## Build strategy

| Layer | Toolchain |
|---|---|
| Host hardware and interactive testing | MSYS2 UCRT64 native Windows tools |
| Reproducible future native binary builds | Docker Linux container cross-compiling to Windows x64 |
| UI/backend development | Windows-host runtime from the new repository |

## Functional milestones

1. Project/toolchain baseline.
2. Docker Windows-x64 cross-toolchain proof.
3. Native dual-device manager/probe.
4. ADS-B decoder feasibility test.
5. NOAA NFM audio receiver.
6. Backend/API and map-first browser interface.
7. Airband AM scanning and state coordination.

## Native device-role manager baseline

The first native executable, `rtl_dual_device_probe`, uses `librtlsdr` to enumerate both dongles sequentially and assigns roles by EEPROM serial number before opening any handles. Its `--open-test` operation opens both receivers by their resolved session indexes and reads a sample block from each. This behavior is the baseline for the later backend-managed ADS-B and audio workers.

## Windows ADS-B decoder baseline

The Windows ADS-B runtime is built around the Windows-native `gvanem/Dump1090` decoder. The backend will not ask Dump1090 to discover the receiver role itself. Instead, the native project-owned probe resolves EEPROM serial `00001090` to its session index and the launcher starts Dump1090 with `--device <resolved_index>`.

Validated initial live profile:

```text
1090.0 MHz / 2.0 MS/s / 48.8 dB fixed tuner gain
```

Dump1090 exposes live state through `/data/aircraft.json`, which is the initial aircraft-data contract for the future local backend and browser UI.

## Backend API process boundary

The first application backend is implemented using the Python standard library and owns Dump1090 lifecycle control. The future browser UI communicates only with backend API endpoints such as `/api/status` and `/api/aircraft`; Dump1090 remains an internal decoder service.

This separation allows later NOAA/Airband controls, map state, settings persistence and trail history to be added without coupling UI code directly to third-party decoder process behavior.
