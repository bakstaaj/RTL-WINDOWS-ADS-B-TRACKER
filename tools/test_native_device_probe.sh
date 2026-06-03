#!/usr/bin/env bash
# Run bounded list, JSON and dual-open validation of the native RTL-SDR device probe.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="${PROJECT_ROOT}/dist/native-windows/rtl_dual_device_probe.exe"
REPORT='/c/Users/jim/Downloads/RTL-Windows-ADS-B-Tracker_Native_Device_Probe_Test_v2.txt'

[[ "${MSYSTEM:-}" == "UCRT64" ]] || {
    printf 'ERROR: Run from MSYS2 UCRT64.\n' >&2
    exit 1
}
[[ -x "${PROBE}" ]] || {
    printf 'ERROR: Probe executable is missing. Run ./tools/build_native_device_probe.sh first.\n' >&2
    exit 1
}

exec > >(tee "${REPORT}") 2>&1

printf 'Native RTL-SDR device probe test - %s\n' "$(date -Is 2>/dev/null || date)"
printf 'Executable: %s\n\n' "${PROBE}"

printf '%s\n' '--- Sequential role discovery ---'
timeout -k 2s 10s "${PROBE}"

printf '\n%s\n' '--- Machine-readable mapping output ---'
timeout -k 2s 10s "${PROBE}" --json

printf '\n%s\n' '--- Dual-handle open/read verification ---'
timeout -k 2s 15s "${PROBE}" --open-test

printf '\nPASS: Native application-owned device-role probe test completed.\n'
printf 'Report saved to: C:\\Users\\jim\\Downloads\\RTL-Windows-ADS-B-Tracker_Native_Device_Probe_Test_v2.txt\n'
