#!/usr/bin/env bash
# Report background Pi UI Windows port service state and log location.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
PID_FILE='runtime/service/pi_port_backend.pid'
LOG_FILE='runtime/logs/pi_port_backend.log'
URL='http://127.0.0.1:8090'

if [[ -s "${PID_FILE}" ]]; then
    PID="$(tr -d '\r\n ' < "${PID_FILE}")"
else
    PID=''
fi

if [[ -n "${PID}" ]] && kill -0 "${PID}" 2>/dev/null; then
    printf 'Pi-port service: running (PID %s)\n' "${PID}"
    printf 'Application: %s/\nLog file:    %s/%s\n' "${URL}" "${ROOT}" "${LOG_FILE}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsS "${URL}/api/status" 2>/dev/null | python3 -m json.tool 2>/dev/null || printf 'Service process is running, but status endpoint is not reachable.\n'
    fi
else
    printf 'Pi-port service: stopped\n'
    printf 'Log file: %s/%s\n' "${ROOT}" "${LOG_FILE}"
    [[ -n "${PID}" ]] && printf 'PID file is stale; run tools/stop_pi_port_service.sh to clear it.\n'
fi
