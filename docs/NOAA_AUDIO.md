# NOAA Weather Radio Audio Baseline

## Validated hardware/profile

| Item | Value |
|---|---|
| Receiver role | NOAA / Airband |
| EEPROM serial | `00000162` |
| Frequency | `162.500 MHz` |
| Modulation | Narrowband FM |
| Audio output rate | `24,000 Hz`, mono signed 16-bit |
| Gain | `40.2 dB` |
| Filter option | De-emphasis enabled |

The standalone concurrency test produced clear voice audio while ADS-B continued decoding. It recorded 32.171 seconds, RMS sample level 1,703.76, peak 14,688 and 0% clipping; ADS-B increased by 10,208 messages during the audio operation.

## Backend-managed baseline

The backend initially provides a bounded record-then-play workflow rather than continuous live streaming:

| Method | Endpoint | Function |
|---|---|---|
| `GET` | `/api/audio/status` | Returns NOAA recording state and metrics |
| `POST` | `/api/audio/noaa/start` | Starts a bounded NOAA recording |
| `POST` | `/api/audio/stop` | Stops an in-progress recording and finalizes WAV |
| `GET` | `/api/audio/latest.wav` | Returns the most recent completed recording |

The development default recording length is 30 seconds. The automated test uses a shorter interval to validate lifecycle behavior quickly.

## Receiver-role safety

NOAA audio operations use the cached `00000162` numeric index from the role mapping completed before ADS-B decoding starts. They do not initiate a fresh serial-role discovery while Dump1090 is active.

When `rtl_fm` opens a numeric device concurrently with the ADS-B decoder, its printed USB serial list may be unreliable on this Windows/libusb setup. The pre-decoder application mapping remains authoritative.

## Browser operation

Start the backend:

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/run_backend_dev.sh
```

Open `http://127.0.0.1:8090/`, choose **Record NOAA**, then play the completed WAV recording in the NOAA Weather Radio panel.

Continuous live browser streaming and civil-airband AM controls are later milestones.
