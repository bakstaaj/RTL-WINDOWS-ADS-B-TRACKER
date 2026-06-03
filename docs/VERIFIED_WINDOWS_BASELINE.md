# Verified Windows Hardware and Toolchain Baseline

**Verified:** 2026-06-03  
**Host:** Windows 11 GOLE2PRO  
**Shell/workspace:** MSYS2 UCRT64 under `~/sdrdev`  
**Receivers:** Two NooElec NESDR Nano 3 RTL2832U/R820T2 units

## Development tools verified

| Component | Result |
|---|---|
| Git | Installed |
| GCC / G++ | Installed in UCRT64 |
| CMake / Ninja / Make | Installed |
| pkg-config | Installed |
| Python | Installed |
| libusb development package | Installed |
| Docker CLI | Installed |
| RTL-SDR utilities/library | `mingw-w64-ucrt-x86_64-rtl-sdr 2.0.2-1` installed |

## Receiver roles already programmed

| Role | Serial number | Session index during validation |
|---|---:|---:|
| NOAA / Airband | `00000162` | `0` |
| ADS-B | `00001090` | `1` |

Numeric indexes are not permanent identity. The application must discover serial-to-index mapping each time receivers are initialized.

## Concurrent capture validation

A staggered overlap test captured both devices concurrently by their resolved numeric indexes:

| Receiver | Frequency | Sample rate | Output bytes | Result |
|---|---:|---:|---:|---|
| ADS-B `00001090` | 1090.000 MHz | 2,400,000 S/s | 24,000,000 | Pass |
| NOAA/Airband `00000162` | 162.500 MHz | 1,008,000 S/s | 4,032,000 | Pass |

## Required Windows runtime rule

A simultaneous startup using two separate `rtl_sdr -d <serial>` commands produced inconsistent USB string enumeration. The working approach is:

1. Enumerate devices sequentially before starting receiver workers.
2. Resolve serial `00001090` and `00000162` to current numeric indexes.
3. Start ADS-B using the resolved ADS-B index.
4. Start NOAA/Airband using the resolved audio index.
5. Avoid concurrent serial-discovery activity in multiple worker processes.

## rtl_sdr finite-capture test note

Do not use an asynchronous `rtl_sdr -n` test whose requested output byte count is an exact multiple of the default output block size. In the upstream utility's callback, cancellation occurs on a partial final block; an exact block multiple can continue until manually stopped or timed out.

## RF validation still required

The concurrent capture validation proves Windows USB/RTL operation and the dual-receiver architecture. It does not yet prove:

- ADS-B packet decoding on the Windows host.
- NOAA demodulated audio quality.
- Airband AM activity detection.
- The significance of the R820T `PLL not locked!` messages observed during raw I/Q tests.

Those checks occur after the first native receiver/decoder build milestones.
