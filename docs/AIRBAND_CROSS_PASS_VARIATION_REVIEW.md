# Cross-Pass Airband Variation Review

## Purpose

Absolute AM level and repeated above-level hits can prioritize candidates, but an intermittent voice transmission may appear as a change between passes rather than a consistently strong level. Cross-pass variation shows how much each channel's measured RMS changes during a multi-pass Survey Scan.

## Variation mark

The **Variation mark** selector offers:

| Setting | Meaning |
|---|---|
| Off | Show variation ratio without highlighting |
| 1.15 × pass low | Mark channels whose highest pass is at least 1.15 times their lowest pass |
| 1.25 × pass low | Default review marker |
| 1.50 × pass low | More selective review marker |

The result table displays a `Var` ratio calculated as highest observed RMS divided by lowest observed RMS across completed passes.

## Interpretation boundary

A **Changing** result may represent a brief transmission, fading, interference or changing noise. It is not confirmed voice activity. The application does not automatically play or hold a channel; the operator selects **Listen** or **Capture 10s**.

## Workflow

This feature is developed on an isolated feature branch with fast source checks and one meaningful live AM/ADS-B validation prior to publication.
