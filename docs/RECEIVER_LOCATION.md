# Receiver Location Settings

## Purpose

Receiver latitude and longitude are application settings rather than compiled map constants. This provides the foundation for distance-ranked airband frequencies and later receiver-dependent coverage/history features.

## Storage

The development backend uses:

```text
runtime/settings/application_settings.json
```

This runtime settings file is excluded from Git. The automated test uses a separate file in `C:\Users\jim\Downloads` and does not change the user's operational location.

## API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/settings` | Returns current saved receiver location |
| `POST` | `/api/settings/receiver-location` | Validates and saves label, latitude and longitude |
| `GET` | `/api/status` | Includes current receiver location for the map UI |

Example request body:

```json
{
  "label": "Stargazer Retreat",
  "latitude": 38.7467,
  "longitude": -105.1783
}
```

The map updates from the saved position immediately. If ADS-B decoding is already running, a decoder restart applies the new home position to Dump1090's internal runtime configuration.

## Browser use

Open **Set receiver location** in the Receiver Status panel, enter a label, latitude and longitude, and select **Save Location**.

## Test

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/test_receiver_location_api.sh
```
