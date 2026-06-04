#!/usr/bin/env bash
# Stop the background Pi UI Windows port service from MSYS2 UCRT64.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
PID_FILE='runtime/service/pi_port_backend.pid'

if [[ ! -s "${PID_FILE}" ]]; then
    printf 'Pi-port service is not recorded as running.\n'
    exit 0
fi
PID="$(tr -d '\r\n ' < "${PID_FILE}")"
if [[ -z "${PID}" ]] || ! kill -0 "${PID}" 2>/dev/null; then
    rm -f "${PID_FILE}"
    printf 'Removed stale Pi-port service PID file.\n'
    exit 0
fi

kill -INT "${PID}" 2>/dev/null || true
for attempt in $(seq 1 40); do
    if ! kill -0 "${PID}" 2>/dev/null; then
        rm -f "${PID_FILE}"
        printf 'Pi-port service stopped.\n'
        exit 0
    fi
    sleep 0.25
done
kill -TERM "${PID}" 2>/dev/null || true
sleep 1
if kill -0 "${PID}" 2>/dev/null; then
    kill -KILL "${PID}" 2>/dev/null || true
fi
rm -f "${PID_FILE}"
printf 'Pi-port service was forced to stop after graceful shutdown timeout.\n'
