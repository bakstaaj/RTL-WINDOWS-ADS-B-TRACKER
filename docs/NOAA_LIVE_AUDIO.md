# Live NOAA Listening Baseline

Live NOAA listening extends the validated bounded recording mode without removing it. The backend reads continuous signed 16-bit PCM output from `rtl_fm` on cached audio receiver serial `00000162` and exposes rolling WAV segments for browser playback.

## API

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/audio/noaa/live/start` | Starts live NOAA capture on cached audio role |
| `GET` | `/api/audio/live/status` | Reports live mode state and sequence |
| `GET` | `/api/audio/live/chunk.wav?after=<sequence>` | Returns the next 500 ms WAV segment |
| `POST` | `/api/audio/live/stop` | Stops live listening |

Live listening and bounded recording are mutually exclusive because both operations use the same receiver. The browser **Listen Live** control queues the returned WAV segments through the Web Audio API.

## Validated profile

```text
Receiver serial: 00000162
Frequency:       162.500 MHz
Mode:            Narrowband FM
Sample rate:     24,000 Hz mono PCM
Gain:            40.2 dB
Processing:      de-emphasis
```

## Test

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/test_backend_live_noaa_api.sh
```
