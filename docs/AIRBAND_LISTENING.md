# Manual Live Airband Listening Baseline

## Purpose

The nearby FAA airband list now provides a manual **Listen** action. A selected channel is validated against the imported FAA catalog, then the dedicated audio receiver tunes to that frequency in AM mode while ADS-B remains active on the other receiver.

## Audio and API design

Airband listening reuses the rolling-WAV browser transport originally validated for NOAA live listening. The two live modes are mutually exclusive because they share receiver serial `00000162`.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/audio/airband/live/start` | Begin AM listening for a selected FAA catalog channel |
| `GET` | `/api/audio/live/status` | Reports active NOAA or airband live selection |
| `GET` | `/api/audio/live/chunk.wav?after=<sequence>` | Returns sequential 500 ms WAV segments |
| `POST` | `/api/audio/live/stop` | Stops live audio |

Airband live-start requests include `frequency_hz`, `serviced_facility` and `frequency_use`. The backend refuses channels that are not present in the generated FAA catalog.

## Baseline RF/audio profile

```text
Mode:             AM
Audio sample rate: 24,000 Hz mono PCM
Gain:              40.2 dB
Receiver serial:   00000162
```

The initial automated validation selects the nearby Fremont County `120.025 MHz` AWOS record as a continuous-audio candidate. Human listening review remains required before publication.

## Test

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/test_backend_live_airband_api.sh
```
