# Live ADS-B Map UI Baseline

## Run

```bash
cd ~/sdrdev/RTL-Windows-ADS-B-Tracker
./tools/run_backend_dev.sh
```

Open:

```text
http://127.0.0.1:8090/
```

## Initial capabilities

- Receiver and decoder status summary with Start/Stop controls.
- Map markers populated only through application endpoint `/api/aircraft`.
- Receiver marker and 5–50 mile range rings.
- Aircraft marker orientation from the received track value.
- Clickable detail view and positioned-aircraft table.
- Browser-session trails colored by altitude:
  - bright green below 5,001 ft
  - dark green below 10,001 ft
  - light blue below 20,001 ft
  - dark blue below 30,001 ft
  - dark yellow below 40,001 ft
  - bright red at 40,001 ft and above

## Map dependencies and local-development tile use

The initial interface loads stable Leaflet `1.9.4` using its documented CDN URLs and integrity hashes. It uses the OpenStreetMap standard raster tile service with visible attribution for local development testing.

OpenStreetMap's community tile service is best-effort and capacity-limited. A distributable or broadly used release should add a configurable production tile-provider setting rather than assuming long-term reliance on the community tile server.

## Receiver location

This baseline exposes an initial Cripple Creek receiver display location through `/api/status`. Settings persistence and an editable receiver-location control are later milestones.
