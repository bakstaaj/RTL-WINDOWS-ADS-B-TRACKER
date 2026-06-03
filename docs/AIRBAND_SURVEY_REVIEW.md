# Survey Result Manual Review

## Purpose

The bounded Survey Scan ranks measured AM audio levels but does not identify usable voice traffic. A level-ranked result is only a candidate. Each completed survey result now provides **Listen** so the operator can audition that exact FAA-validated channel without finding it again in the full nearby-channel list.

## Behavior

- Survey Scan remains silent while measuring.
- Result rows are sorted by measured RMS and show a **Listen** action.
- Selecting **Listen** invokes the existing FAA-catalog-validated live AM transport for that exact result record.
- While a survey is running, result and nearby-channel Listen actions remain disabled.
- Listening remains manual; no threshold automatically selects, holds or plays a channel.

## Test

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/test_airband_survey_review_action.sh
```

The automated validation checks the browser wiring and opens a nearby `120.025 MHz` AWOS result through the existing live AM API while verifying ADS-B continuity.
