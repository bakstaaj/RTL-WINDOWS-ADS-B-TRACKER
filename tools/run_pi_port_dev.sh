#!/usr/bin/env bash
# Run the Pi UI Windows port interactively for development/debugging.
# Normal use should call tools/start_pi_port_service.sh instead.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
mkdir -p runtime/logs
exec python3 src/backend/rtl_windows_pi_port_backend.py \
  --host 127.0.0.1 \
  --port 8090 \
  --dump-http-port 18080 \
  --log-file runtime/logs/pi_port_backend.log \
  --foreground-log \
  --autostart \
  "$@"
