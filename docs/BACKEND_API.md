# Backend API Baseline

## Purpose

The local Python backend owns the initial Windows application process boundary. It runs without third-party Python packages, resolves RTL-SDR device roles through the native probe, starts the validated Dump1090 runtime, and proxies aircraft state to a stable application-facing API.

## Start the development backend

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/run_backend_dev.sh
```

Default development addresses:

| Service | Address |
|---|---|
| Application backend API | `http://127.0.0.1:8090` |
| Internal Dump1090 JSON service | `http://127.0.0.1:18080` |

The browser UI should call the application backend, not Dump1090 directly.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | Basic backend liveness check |
| `GET` | `/api/status` | Receiver roles, decoder running state, RF profile and current counts |
| `GET` | `/api/receiver-roles` | Current EEPROM-serial-to-session-index mapping |
| `GET` | `/api/aircraft` | Proxied Dump1090 aircraft JSON |
| `POST` | `/api/decoder/start` | Resolve roles and start ADS-B decoder |
| `POST` | `/api/decoder/stop` | Stop ADS-B decoder |

## Startup safety rule

The backend never launches the ADS-B decoder by assumed device order. It first runs `rtl_dual_device_probe --json`, confirms:

```text
00001090 = ADS-B
00000162 = NOAA / Airband
```

and only then launches Dump1090 with the numeric ADS-B session index.

## ADS-B runtime profile

```text
Frequency:   1090.0 MHz
Sample rate: 2.0 MS/s
Tuner gain:  48.8 dB
```

## Test

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/test_backend_adsb_api.sh
```

The test passes when the service reports correct receiver roles, exposes a JSON-ready decoder, and proxies a positive ADS-B message count. Aircraft display records are verified when present but are not required in every short RF observation window.
