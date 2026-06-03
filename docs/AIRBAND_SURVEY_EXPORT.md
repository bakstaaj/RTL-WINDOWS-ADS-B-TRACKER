# Export Completed Airband Survey CSV

## Purpose

Completed Survey Scan results can now be downloaded as a CSV evidence record for offline review. Export supports comparisons between plans, locations and future manual listening/capture observations without making automatic traffic decisions.

## Exported fields

Each result row includes:

- Export timestamp and result rank.
- FAA channel frequency, facility, use, category and distance.
- Average RMS level, candidate hit count and measured passes.
- Cross-pass variation ratio and the displayed manual-review label.
- Survey category, radius, sample duration, pass count and threshold settings.
- Per-pass RMS values.

## Behavior boundary

**Export Survey CSV** is enabled only when completed Survey Scan results are present. It exports already-computed browser measurements and does not retune a receiver, request audio, play audio, classify voice traffic or hold a frequency.

## Validation policy

This is a UI/export-only milestone. Under the consolidated development workflow, it uses source/syntax/export-contract checks rather than an additional live SDR test because RF/audio/backend behavior is unchanged.
