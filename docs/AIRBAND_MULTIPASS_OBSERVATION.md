# Multi-Pass Airband Candidate Observation

## Purpose

A single level measurement may reflect a brief transmission, a continuous station, a carrier or noise. Multi-pass observation lets the operator repeat a bounded Survey Scan and see how often a frequency exceeds the selected candidate-level rule.

## Survey control

The **Passes** setting offers 1, 3 or 5 complete bounded sweeps. For each pass:

1. The selected nearby FAA frequencies are sampled in AM mode.
2. The median RMS level for that pass is computed.
3. A channel earns a hit only when its sample is at or above the selected candidate multiplier for that pass.

Results show average RMS and `hits / measured passes`. **Repeat hit** indicates above-level measurements in more than one pass.

## Interpretation boundary

A repeat hit is still a measurement observation only. It may indicate a persistent weather broadcast or interference rather than voice traffic. Survey Scan never automatically tunes for playback, holds a frequency, or declares traffic. The operator continues with **Listen** or **Capture 10s**.

## Workflow

This feature is developed under the feature-branch workflow with lightweight source checks and one meaningful live validation before publication.
