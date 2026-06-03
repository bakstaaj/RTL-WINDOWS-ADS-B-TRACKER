# FAA Airband Catalog Baseline

## Structured data source

The application uses official FAA NASR **Frequency Data** `FRQ.csv` as its normalized airband source. It provides `FREQ`, `FREQ_USE`, facility identity, serviced-location coordinates, city and state directly. The baseline therefore does not parse ATC free-text remarks.

## Generated runtime catalog

The downloaded FAA ZIP is imported into excluded runtime data:

```text
runtime/settings/faa_airband_catalog.json
```

Import a downloaded FAA cycle with:

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/import_faa_airband_catalog.sh /c/Users/jim/Downloads/FAA_NASR_2026-05-14_FRQ_CSV.zip
```

## API and UI

`GET /api/airband/channels?radius_miles=100&limit=20` returns VHF civil airband rows from `118.000` through `136.975 MHz`, ordered by distance from the persisted receiver location. The initial **Nearby Airband Channels** browser panel is read-only; audio tune/listen/scan controls are a later milestone.

## Test

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/test_airband_catalog_api.sh
```
