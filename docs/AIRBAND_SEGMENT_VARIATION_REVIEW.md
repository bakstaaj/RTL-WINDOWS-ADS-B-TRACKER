# Within-Sample Segment Variation Review

## Purpose

A brief airband transmission can appear and disappear inside one Survey Scan observation, even when a channel does not rank strongly across complete passes. Survey audio already arrives in 500 ms WAV segments. This feature measures change between those existing segments without adding any radio or audio-transport operation.

## Segment-change mark

The **Segment change** selector offers:

| Setting | Meaning |
|---|---|
| Off | Show within-sample ratio without highlighting |
| 1.15 × segment low | Mark modest changes among received 500 ms segments |
| 1.25 × segment low | Default manual-review marker |
| 1.50 × segment low | More selective marker |

For each frequency and pass, segment variation is the largest 500 ms RMS divided by the smallest 500 ms RMS in that observation. The displayed `Seg` value is the maximum segment-variation ratio observed across completed passes.

## Interpretation boundary

A **Segment change** can represent speech onset, modulation, fading, interference or changing noise. It is not confirmed voice activity and does not start playback or hold a channel. The operator uses **Listen**, **Capture 10s**, or **Export Survey CSV** for review.

## Validation policy

This is browser-side calculation and export logic using audio segments already collected by Survey Scan. It is validated with source, syntax and deterministic measurement-contract tests without repeating unchanged SDR hardware validation.
