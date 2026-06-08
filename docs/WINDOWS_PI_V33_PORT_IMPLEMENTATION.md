<!-- RTP-PI-V33-WINDOWS-PORT -->

# Windows Port of Raspberry Pi v3.3.0 Functional Enhancements

This checkpoint ports the safest browser/backend compatibility pieces from the Raspberry Pi v3.3.0 functional baseline into the Windows application without disturbing the validated Windows ADS-B, NOAA, and Airband receiver workflows.

## Implemented in this patch

- Added `/api/aircraft/local?hex=<ICAO_HEX>` as a Pi-compatible alias for the Windows local aircraft hex database lookup.
- Added AirLabs callsign normalization so airline-style callsigns with leading zeros can retry with the numeric zero padding removed. Example: `KAL032` first checks `KAL032`, then `KAL32`.
- Added backend and browser route-source classification for private/charter prefixes and registration-style tail-number callsigns.
- Added active trail cleanup when an aircraft leaves the current live aircraft set. The visible live trail layer is removed, but retained browser/backend history is not erased.
- Added a map marker double-click handler that selects the aircraft and calls the existing aircraft details popup function when present.

## Validation checklist

1. Start the Windows Pi-port backend and open the UI.
2. Confirm the browser console has no JavaScript syntax errors.
3. Double-click an aircraft icon on the map. The aircraft should be selected, and the full detail popup should open when the detail-popup function exists in the current UI build.
4. Watch an aircraft leave range. Its marker and active visible trail should disappear; Restore History should still be able to recover retained trail history.
5. Test route lookup examples:
   - `KAL032` should include lookup variants `KAL032`, `KAL32`.
   - `KOW523` should classify as Baker Aviation / Rodeo when no AirLabs route exists.
   - `LYM3583` should classify as Key Lime Air when no AirLabs route exists.
   - `N653JC` should classify as private/general aviation tail-number route unavailable.
6. Test local aircraft metadata lookup:
   - `/api/aircraft/local?hex=AE68F2`
   - `/api/aircraft/hex?hex=AE68F2`
   Both should return the same local hex DB response shape.

## Notes

The patch is intentionally idempotent and tagged with `RTP-PI-V33-WINDOWS-PORT`. Re-running the patch should not duplicate the inserted helper blocks.
