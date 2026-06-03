# Bounded Airband Capture Review

## Purpose

Survey Scan levels remain candidate measurements rather than traffic detection. Manual **Capture 10s** actions let an operator save selected FAA-validated AM audio for later listening and comparison without automatically declaring a channel active.

## Behavior

- Nearby FAA channel rows and completed Survey Scan results offer **Capture 10s**.
- Capture uses the existing validated airband live-AM rolling-WAV API.
- During a capture, the browser receives audio silently and assembles a labeled mono PCM WAV download.
- Capture does not automatically start from a survey score.
- Manual **Listen** remains available for immediate review when capture or survey activity is not running.

## Future detector value

Saved examples provide a practical basis for comparing speech, weather broadcast, carrier noise and silence before any future activity/hold rule is considered.

## Safety boundary

Capture is operator-triggered. It does not:

- Detect voice traffic.
- Automatically choose, hold or play a channel.
- Change the FAA catalog or saved receiver location.

## Test

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/test_airband_capture_review_action.sh
```

The test opens the known nearby `120.025 MHz` AWOS record through the established AM transport, produces a review WAV and verifies ADS-B continuity.
