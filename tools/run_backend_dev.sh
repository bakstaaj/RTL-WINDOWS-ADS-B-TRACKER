#!/usr/bin/env bash
# Launch the local application backend with ADS-B autostart.
# Intended environment: MSYS2 UCRT64.

set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ "${MSYSTEM:-}" == "UCRT64" ]] || {
    printf 'ERROR: Run from MSYS2 UCRT64.\n' >&2
    exit 1
}

exec python3 "${PROJECT_ROOT}/src/backend/rtl_windows_backend.py" \
    --host 127.0.0.1 \
    --port 8090 \
    --dump-http-port 18080 \
    --autostart
