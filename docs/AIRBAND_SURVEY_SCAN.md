# Bounded Airband Survey Scan Baseline

## Why this is a survey rather than automatic activity scanning

The first runtime survey sampled 15 nearby FAA-ranked AM frequencies while ADS-B remained active. The measured RMS sample values ranged from approximately 363 to 676, with a median of 490.46. None exceeded the exploratory twice-median level of 980.92.

That result validates retuning and measurement, but it does not establish a reliable voice-traffic detector. Carrier presence, receiver noise and local interference can elevate RMS without usable speech, while a brief transmission can be missed in a bounded sample.

## Browser behavior

The **Nearby Airband Channels** panel now provides:

- **Listen** for manual AM monitoring of a specific FAA channel.
- **Run Survey Scan** to measure up to 10 nearby unique frequencies.
- **Stop Scan** to stop the bounded survey.

Survey Scan fetches short rolling WAV segments through the existing validated manual-listening APIs and computes an RMS ranking in the browser. It does **not** play audio automatically, declare traffic active, or hold a frequency.

## Next detector milestone

A later automatic scanner should be based on additional validation, such as speech/audio review and a configurable hold rule, rather than a fixed unverified RMS threshold.

## Test

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/test_browser_airband_survey_scan.sh
```
