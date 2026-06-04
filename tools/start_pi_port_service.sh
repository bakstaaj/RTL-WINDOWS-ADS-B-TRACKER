#!/usr/bin/env bash
# Start the Pi UI Windows port quietly in the background from MSYS2 UCRT64.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
RUNTIME='runtime/service'
LOG_DIR='runtime/logs'
PID_FILE="${RUNTIME}/pi_port_backend.pid"
LOG_FILE="${LOG_DIR}/pi_port_backend.log"
HOST='127.0.0.1'
PORT='8090'
mkdir -p "${RUNTIME}" "${LOG_DIR}"

if [[ -s "${PID_FILE}" ]]; then
    EXISTING_PID="$(tr -d '\r\n ' < "${PID_FILE}")"
    if [[ -n "${EXISTING_PID}" ]] && kill -0 "${EXISTING_PID}" 2>/dev/null; then
        printf 'Pi-port service is already running (PID %s).\n' "${EXISTING_PID}"
        printf 'Open: http://%s:%s/\nLog:  %s/%s\n' "${HOST}" "${PORT}" "${ROOT}" "${LOG_FILE}"
        exit 0
    fi
    rm -f "${PID_FILE}"
fi

# A stale or manually started instance should fail quickly with a useful log entry.
nohup python3 src/backend/rtl_windows_pi_port_backend.py \
    --host "${HOST}" \
    --port "${PORT}" \
    --dump-http-port 18080 \
    --log-file "${LOG_FILE}" \
    --log-level INFO \
    --autostart \
    </dev/null >/dev/null 2>&1 &
PID="$!"
printf '%s\n' "${PID}" > "${PID_FILE}"

for attempt in $(seq 1 20); do
    if ! kill -0 "${PID}" 2>/dev/null; then
        rm -f "${PID_FILE}"
        printf 'ERROR: Pi-port service exited during startup. Recent diagnostics:\n' >&2
        tail -n 30 "${LOG_FILE}" >&2 2>/dev/null || true
        exit 1
    fi
    if curl -fsS "http://${HOST}:${PORT}/api/status" >/dev/null 2>&1; then
        printf 'Pi-port service started in background (PID %s).\n' "${PID}"
        printf 'Open: http://%s:%s/\nLog:  %s/%s\n' "${HOST}" "${PORT}" "${ROOT}" "${LOG_FILE}"
        exit 0
    fi
    sleep 0.25
done

printf 'ERROR: Pi-port service did not become reachable. Recent diagnostics:\n' >&2
tail -n 30 "${LOG_FILE}" >&2 2>/dev/null || true
exit 1
