# External Dependency Policy

External source trees and built third-party artifacts are not committed here by default.

Planned dependencies to evaluate and pin in build tooling:

- `librtlsdr` / RTL-SDR utilities for NooElec RTL2832U/R820T2 receiver access.
- `libusb` for RTL-SDR USB access.
- `readsb` or an alternative ADS-B decoder after the Windows feasibility test.

The application must preserve fixed logical device roles by RTL-SDR EEPROM serial number.
