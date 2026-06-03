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

## Live map browser interface

The initial browser UI is served directly by the Python backend and consumes `/api/status` and `/api/aircraft`. It includes receiver rings, oriented aircraft markers, a selected-aircraft detail view and browser-session trails. Keeping Dump1090 internal preserves the application API boundary for later audio controls, persisted settings and history restoration.

## NOAA audio operation baseline

The backend owns a second audio operation manager for the NOAA/Airband receiver. Initial NOAA operation is a bounded NFM recording at 162.500 MHz that produces a WAV file served to the browser for playback. It uses the cached numeric index for serial `00000162` from the same pre-decoder role mapping that assigns ADS-B serial `00001090`; it does not enumerate serial roles concurrently with active ADS-B decoding.

## Live NOAA audio delivery

Live NOAA listening uses the cached audio-role index for serial `00000162`. The backend launches `rtl_fm` with stdout PCM output, packages sequential 500 ms PCM blocks as small WAV responses, and lets the browser queue them through the Web Audio API. Live listening and bounded record/play are mutually exclusive operations on the same audio receiver.

## Persisted receiver location

The backend owns validated receiver-location settings stored in excluded runtime settings JSON. `/api/status` and `/api/settings` expose the saved location to the browser map; decoder configuration applies that location at decoder startup. This setting is the spatial reference for future airband-channel distance sorting and receiver coverage features.

## FAA airband catalog and ranked-channel API

Official FAA NASR `FRQ.csv` is imported into an excluded runtime JSON catalog. The backend filters civil VHF channels and ranks them by distance from the persisted receiver location before serving `/api/airband/channels`. `FRQ.csv` supplies normalized frequency/use/facility/location fields directly, so the baseline avoids parsing free-text ATC remarks.

## FAA-selected live airband audio

Manual airband listening accepts only a selected record present in the imported FAA runtime catalog, then tunes the cached audio-role receiver in AM mode. It reuses the existing live rolling-WAV transport and remains mutually exclusive with NOAA live/listen/record operations on serial `00000162`.

## Bounded airband survey measurement

The browser can sequence existing FAA-validated AM live-audio requests across a small bounded set of nearby unique frequencies, decode rolling WAV segments without speaker playback, and display RMS rankings. This deliberately avoids introducing an autonomous detection/hold policy until local measurements and listening review support a validated activity discriminator.

## Operator-configured airband survey planning

The browser supplies bounded survey-plan controls that filter the existing FAA-ranked channel API response before making FAA-validated live AM requests. Category filtering and sample-duration choices remain UI-side measurement behavior; no autonomous traffic detector or backend scan scheduler is introduced.

## Manual review of ranked survey results

Ranked browser-side Survey Scan results retain their underlying FAA catalog record. A manual result-row Listen action passes that record to the already validated AM live-listening path, providing operator confirmation without introducing backend auto-selection, voice detection, channel hold or automatic playback.

## Operator-triggered bounded Airband Capture

The browser reuses the existing FAA-validated live AM segment endpoint to receive a fixed 10-second selected-channel sample without speaker playback, merges decoded mono audio into a client-side WAV download, and labels it from the FAA result record. No new backend tuner mode or automatic detector/hold state is introduced.
