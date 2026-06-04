#!/usr/bin/env bash
# RTL-Windows-ADS-B-Tracker restart_pi_port_service helper - Step 84
# Stops and starts the quiet Pi-port browser backend service in one command.
#
# Run from the repository:
#   ./tools/restart_pi_port_service.sh
#
# Or run from any directory:
#   ~/sdrdev/RTL-Windows-ADS-B-Tracker/tools/restart_pi_port_service.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
STOP_SCRIPT="${SCRIPT_DIR}/stop_pi_port_service.sh"
START_SCRIPT="${SCRIPT_DIR}/start_pi_port_service.sh"

section() {
    printf '\n====================================================================\n'
    printf '%s\n' "$1"
    printf '====================================================================\n'
}

[[ -x "${STOP_SCRIPT}" ]] || {
    printf 'ERROR: Required executable is missing: %s\n' "${STOP_SCRIPT}" >&2
    printf 'Run: chmod +x "%s"\n' "${STOP_SCRIPT}" >&2
    exit 1
}
[[ -x "${START_SCRIPT}" ]] || {
    printf 'ERROR: Required executable is missing: %s\n' "${START_SCRIPT}" >&2
    printf 'Run: chmod +x "%s"\n' "${START_SCRIPT}" >&2
    exit 1
}

section "Stop Pi-port service"
cd "${PROJECT}"
"${STOP_SCRIPT}"

section "Start Pi-port service"
"${START_SCRIPT}"

section "Pi-port service restart complete"
printf 'Project: %s\n' "${PROJECT}"
printf 'Refresh the browser with Ctrl+F5 when testing updated UI or backend source.\n'
