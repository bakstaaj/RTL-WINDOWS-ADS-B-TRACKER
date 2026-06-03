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

## NOAA Weather Radio recording baseline

The second RTL-SDR receiver supports backend-managed NOAA recording. Serial `00000162` records the validated local channel at `162.500 MHz` using NFM, 24 kHz output, 40.2 dB gain and de-emphasis while ADS-B continues on serial `00001090`.

The initial UI provides a bounded Record NOAA / playback workflow. See `docs/NOAA_AUDIO.md`.

## Live NOAA listening baseline

The NOAA/Airband receiver now also supports local browser live listening through rolling backend WAV segments while preserving the bounded recording workflow. Use **Listen Live** in the browser interface. See `docs/NOAA_LIVE_AUDIO.md`.

## Receiver location settings

The browser Receiver Status panel now supports a persisted receiver label, latitude and longitude. The backend stores operational settings outside tracked source, and the saved location provides the reference point for upcoming distance-ranked airband channel support. See `docs/RECEIVER_LOCATION.md`.

## FAA distance-ranked airband catalog baseline

The application imports official FAA NASR `FRQ.csv` airband records into excluded runtime data and displays nearby channels ordered from the saved receiver location. The first catalog baseline is read-only; audio tune/listen/scan controls follow after presentation validation. See `docs/AIRBAND_CATALOG.md`.

## Manual live airband listening baseline

Each nearby FAA airband channel can be selected for live AM listening on the dedicated audio receiver while ADS-B continues operating. The backend validates the selected frequency against the imported FAA catalog before tuning and reuses rolling WAV/Web Audio delivery. See `docs/AIRBAND_LISTENING.md`.

## Bounded airband Survey Scan baseline

The Nearby Airband Channels panel supports a bounded **Survey Scan** that measures and ranks short AM audio samples from nearby unique FAA frequencies while preserving manual Listen behavior. This baseline is deliberately observational: it does not claim traffic detection or automatically hold/play a channel. See `docs/AIRBAND_SURVEY_SCAN.md`.

## Configurable Airband Survey Plan

The bounded Survey Scan panel supports operator-selected radius, number of unique frequencies, sample duration and channel category grouping. These options make the measurement workflow useful for continuous Weather/ATIS signals or sporadic operational channels without adding unvalidated automatic activity/hold behavior. See `docs/AIRBAND_SURVEY_PLAN.md`.

## Survey result manual Listen review

Completed Survey Scan result rows include a manual **Listen** action, allowing an operator to audition a ranked FAA-validated AM candidate without locating it again in the full channel list. Survey Scan remains measurement-only and silent until the operator selects a result. See `docs/AIRBAND_SURVEY_REVIEW.md`.

## Bounded Airband Capture review

Nearby FAA channels and completed Survey Scan results can be captured manually to a labeled 10-second WAV download through the existing validated AM transport. This supplies review material for later detector design while retaining an operator-triggered, no-auto-hold boundary. See `docs/AIRBAND_CAPTURE_REVIEW.md`.

## Development workflow

New milestones use isolated feature branches, lightweight source checks and one meaningful live hardware/API validation before a validated commit is fast-forwarded to `main` and published. Failed work remains off `main` for targeted repair or rollback. See `docs/DEVELOPMENT_WORKFLOW.md`.

## Candidate-level airband review

Survey Scan supports an operator-selected measured-level rule that marks above-level candidates relative to the survey median. Candidate status is measurement-only and requires manual Listen or Capture review; it does not declare traffic or automatically hold/play a channel. See `docs/AIRBAND_CANDIDATE_LEVEL_REVIEW.md`.

## Multi-pass candidate observation

Survey Scan supports repeated bounded passes and displays above-level hit counts per FAA channel. Repeat hits improve operator prioritization for Listen/Capture review but remain measurements only, not traffic detection or automatic hold behavior. See `docs/AIRBAND_MULTIPASS_OBSERVATION.md`.

## Cross-pass airband variation review

Survey Scan can mark channels whose measured RMS changes across completed passes, helping prioritize intermittent candidates for manual Listen/Capture review. Variation is a review cue only and does not declare traffic or automatically hold/play a channel. See `docs/AIRBAND_CROSS_PASS_VARIATION_REVIEW.md`.

## Completed Survey CSV export

Completed Survey Scan results can be exported to CSV with FAA channel details, survey-plan parameters, RMS levels, candidate hits, variation ratio and manual-review labels. Export is evidence collection only and performs no new radio/audio action. See `docs/AIRBAND_SURVEY_EXPORT.md`.

## Within-sample airband segment variation review

Survey Scan can mark channels whose level changes among the 500 ms audio segments already collected within an observation. This adds an intermittent-signal review cue without changing radio/audio transport or declaring voice activity. See `docs/AIRBAND_SEGMENT_VARIATION_REVIEW.md`.
