# Native Dual RTL-SDR Device Probe

## Purpose

`rtl_dual_device_probe` is the first application-owned native Windows component. It performs sequential device discovery using `librtlsdr`, assigns fixed logical roles using EEPROM serial numbers, and can validate that both receiver handles can be opened in one process.

## Fixed role assignment

| Logical role | Required serial | Test frequency | Test sample rate |
|---|---:|---:|---:|
| ADS-B | `00001090` | 1090.000 MHz | 2,400,000 S/s |
| NOAA / Airband | `00000162` | 162.500 MHz | 1,008,000 S/s |

## Why this probe exists

Initial raw-tool testing established that two independent `rtl_sdr -d <serial>` startup operations can collide during simultaneous USB serial enumeration on this Windows/libusb setup. The application must therefore discover the serial-to-index mapping once, sequentially, before receiver workers begin.

## Use

From MSYS2 UCRT64:

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/build_native_device_probe.sh
./tools/test_native_device_probe.sh
```

Direct operations:

```bash
./dist/native-windows/rtl_dual_device_probe.exe
./dist/native-windows/rtl_dual_device_probe.exe --json
./dist/native-windows/rtl_dual_device_probe.exe --open-test
```

`--open-test` opens ADS-B first and NOAA/Airband second by their resolved indexes, then reads one I/Q block from each while both device handles are open. It performs no EEPROM writes and produces no persistent capture files.

## Future integration

The backend/device manager should use the same serial-to-index discovery rule and make its resolved session mapping available through application status diagnostics.
