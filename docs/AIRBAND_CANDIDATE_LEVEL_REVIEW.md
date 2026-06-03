# Candidate-Level Review for Airband Survey Scan

## Purpose

Survey Scan already measures AM audio levels and supports manual Listen/Capture review. This feature adds an operator-selected **Candidate level** rule that highlights results whose measured RMS level is above a multiplier of the survey median.

## Candidate rule options

| Setting | Behavior |
|---|---|
| Off | Show measured results without candidate highlighting |
| 1.25 × median | Highlight channels at or above 1.25 times median RMS |
| 1.50 × median | Highlight channels at or above 1.50 times median RMS |
| 2.00 × median | Highlight channels at or above 2.00 times median RMS |

## Interpretation boundary

An **Above level** result is only a measurement candidate. It can reflect speech, a continuous weather broadcast, a carrier, local interference or noise. The application does not declare voice traffic or automatically hold/play any channel. The operator uses **Listen** or **Capture 10s** for review.

## Validation workflow

This milestone uses the consolidated feature-branch workflow: fast source checks followed by one live FAA-selected AM/ADS-B concurrency validation before committing and publishing validated source.
