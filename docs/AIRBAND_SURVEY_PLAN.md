# Configurable Airband Survey Plan

## Purpose

The bounded **Survey Scan** remains a measurement tool rather than an automatic traffic detector. Operator controls make it practical to focus measurements without introducing an unvalidated activity/hold policy.

## Browser controls

| Setting | Options | Purpose |
|---|---|---|
| Radius | 25, 50, 100, 200 miles | Limits FAA-ranked channels around saved receiver location |
| Channels | 5, 10, 20 unique frequencies | Bounds survey duration |
| Sample | 1, 2, 3 seconds per channel | Trades speed for measurement stability |
| Category | All, Weather/ATIS, CTAF/UNICOM, Tower/Ground/Approach | Focuses the channel set |

**Weather / ATIS** is useful when evaluating continuous or frequently repeated sources. **CTAF / UNICOM** and control categories are more likely to be silent during a short survey unless traffic is active.

## Safety boundary

Survey Scan calculates and ranks measured AM audio levels. It does not:

- Claim that a channel contains voice traffic.
- Automatically hold on a frequency.
- Automatically play a measured channel.
- Change the saved receiver location or generated FAA catalog.

Manual **Listen** remains the operator confirmation path.

## Test

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/test_airband_survey_plan_api.sh
```

The automated validation executes a bounded Weather/ATIS plan while confirming ADS-B remains active.
