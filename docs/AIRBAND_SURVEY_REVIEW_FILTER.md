# Airband Survey Review Filter and Reason Labels

## Purpose

Survey Scan can now produce several independent review cues: above-level hits, repeat hits, pass-to-pass changes and within-sample segment changes. The **Review filter** focuses displayed results on one cue or on all marked records, while the **Reason** column states why each result is shown for review.

## Filters

| Selection | Displayed completed results |
|---|---|
| All results | Every measured FAA channel |
| Marked results only | Any result with an above-level, pass-change or segment-change mark |
| Above level | Any result above the selected per-pass level rule |
| Repeat hit | Results above level on more than one pass |
| Pass change | Results meeting the selected cross-pass variation rule |
| Segment change | Results meeting the selected within-sample segment rule |

## Evidence boundary

Review filters and reasons summarize measurement cues only. They do not identify confirmed voice traffic, cause retuning, play audio, or automatically hold a channel. The operator remains responsible for selecting **Listen** or **Capture 10s**.

## CSV evidence

CSV exports continue to include all completed survey results, independent of the displayed filter, and now include review reasons and the currently selected display filter for context.

## Validation policy

Filtering and reason labeling are browser-side presentation/export logic over completed measurements. They are validated through deterministic classification and export-contract tests without a redundant SDR test.
