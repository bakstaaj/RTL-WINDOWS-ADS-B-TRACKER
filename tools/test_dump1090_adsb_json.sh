#!/usr/bin/env bash
# Run a bounded live JSON validation of the built Dump1090 ADS-B decoder.
# Intended environment: MSYS2 UCRT64.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="${PROJECT_ROOT}/dist/native-windows/rtl_dual_device_probe.exe"
DUMP_EXE="${PROJECT_ROOT}/dist/third_party/dump1090/dump1090.exe"
AIRPORT_DB="${PROJECT_ROOT}/dist/third_party/dump1090/airport-codes.csv"
TEST_DIR="${PROJECT_ROOT}/test_output/dump1090_runtime"
CONFIG="${TEST_DIR}/dump1090_adsb_runtime.cfg"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Dump1090_Integrated_Runtime_Test.txt"
JSON_OUT="${OUT}/RTL-Windows-ADS-B-Tracker_Dump1090_Integrated_aircraft.json"
RUN_LOG="${OUT}/RTL-Windows-ADS-B-Tracker_Dump1090_Integrated_run.log"

HTTP_PORT=18080
SBS_PORT=13003
OBSERVE_SECONDS=45
DUMP_PID=''

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

stop_decoder() {
    if [[ -n "${DUMP_PID}" ]] && kill -0 "${DUMP_PID}" 2>/dev/null; then
        kill -INT "${DUMP_PID}" 2>/dev/null || true
        sleep 1
        kill -KILL "${DUMP_PID}" 2>/dev/null || true
        wait "${DUMP_PID}" 2>/dev/null || true
    fi
    DUMP_PID=''
}
trap stop_decoder EXIT

[[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Run from MSYS2 UCRT64."
[[ -x "${PROBE}" ]] || fail "Build the native device-role probe first."
[[ -x "${DUMP_EXE}" ]] || fail "Run ./tools/build_dump1090_windows.sh first."
[[ -s "${AIRPORT_DB}" ]] || fail "Packaged airport-codes.csv is missing; rerun ./tools/build_dump1090_windows.sh."
for command_name in python3 curl cygpath; do
    command -v "${command_name}" >/dev/null 2>&1 || fail "${command_name} is missing."
done

mkdir -p "${TEST_DIR}" "${OUT}"
exec > >(tee "${REPORT}") 2>&1

printf 'RTL-Windows-ADS-B-Tracker integrated Dump1090 runtime test - %s\n' "$(date -Is 2>/dev/null || date)"
MAPPING_JSON="$("${PROBE}" --json)"
printf 'Device mapping: %s\n' "${MAPPING_JSON}"
ADSB_INDEX="$(
    printf '%s' "${MAPPING_JSON}" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"]; assert d["adsb"]["serial"] == "00001090"; print(d["adsb"]["index"])' |
    tr -d '\r'
)"
printf 'Starting ADS-B decoder for serial 00001090 at resolved index %s.\n' "${ADSB_INDEX}"
printf 'Validated receive profile: 1090.0 MHz, 2.0 MS/s, 48.8 dB gain.\n'
AIRPORT_DB_WIN="$(cygpath -w "${AIRPORT_DB}")"
printf 'Packaged airport database: %s\n' "${AIRPORT_DB_WIN}"

cat > "${CONFIG}" <<CFG
# Generated runtime-test configuration. This file is excluded from Git.
aircrafts = NUL
airports = ${AIRPORT_DB_WIN}
homepos = 38.7467,-105.1783
location = no
logfile = NUL
silent = true
error-correct1 = true
error-correct2 = true
agc = false
gain = 48.8
freq = 1090.0M
phase-enhance = false
samplerate = 2M
DC-filter = true
measure-noise = true
rtlsdr-calibrate = false
rtlsdr-ppm = 0
net-http-port = ${HTTP_PORT}
net-ri-port = 13001
net-ro-port = 13002
net-sbs-port = ${SBS_PORT}
web-send-rssi = true
CFG

rm -f "${JSON_OUT}" "${RUN_LOG}"
(
    cd "$(dirname "${DUMP_EXE}")"
    ./dump1090.exe --config "${CONFIG}" --device "${ADSB_INDEX}" --net
) >"${RUN_LOG}" 2>&1 &
DUMP_PID=$!

ENDPOINT=''
for attempt in $(seq 1 20); do
    for candidate in '/data/aircraft.json' '/data.json'; do
        if curl -fsS "http://127.0.0.1:${HTTP_PORT}${candidate}" >"${JSON_OUT}.startup" 2>/dev/null; then
            ENDPOINT="${candidate}"
            break 2
        fi
    done
    kill -0 "${DUMP_PID}" 2>/dev/null || break
    sleep 1
done
[[ -n "${ENDPOINT}" ]] || {
    sed -n '1,180p' "${RUN_LOG}" || true
    fail "Dump1090 did not expose its aircraft JSON endpoint."
}
printf 'JSON endpoint ready: %s\n' "${ENDPOINT}"

MAX_MESSAGES=0
MAX_AIRCRAFT=0
for second in $(seq 1 "${OBSERVE_SECONDS}"); do
    curl -fsS "http://127.0.0.1:${HTTP_PORT}${ENDPOINT}" >"${JSON_OUT}"
    read -r MESSAGES AIRCRAFT < <(
        python3 - "${JSON_OUT}" <<'PY' | tr -d '\r'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
rows = data.get("aircraft", []) if isinstance(data, dict) else data if isinstance(data, list) else []
print(int(data.get("messages", 0)) if isinstance(data, dict) else 0, len(rows))
PY
    )
    (( MESSAGES > MAX_MESSAGES )) && MAX_MESSAGES="${MESSAGES}" || true
    (( AIRCRAFT > MAX_AIRCRAFT )) && MAX_AIRCRAFT="${AIRCRAFT}" || true
    if (( second == 1 || second % 5 == 0 || AIRCRAFT > 0 )); then
        printf 'Second %s: messages=%s aircraft=%s\n' "${second}" "${MESSAGES}" "${AIRCRAFT}"
    fi
    if (( AIRCRAFT > 0 )); then
        break
    fi
    sleep 1
done

stop_decoder

printf '\nMaximum messages observed: %s\n' "${MAX_MESSAGES}"
printf 'Maximum aircraft observed: %s\n' "${MAX_AIRCRAFT}"
python3 - "${JSON_OUT}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
rows = data.get("aircraft", [])
print("JSON keys:", sorted(data.keys()))
for row in rows[:5]:
    print("Aircraft sample:", {k: row.get(k) for k in ("hex", "flight", "altitude", "lat", "lon", "speed", "track", "messages", "seen") if k in row})
PY
printf '\nDecoder log excerpt:\n'
sed -n '1,80p' "${RUN_LOG}" || true

if (( MAX_AIRCRAFT > 0 )); then
    printf '\nPASS: Dump1090 served live aircraft JSON using the application-resolved ADS-B receiver.\n'
else
    printf '\nPARTIAL: Dump1090 received %s messages but no aircraft entry was retained in this observation window.\n' "${MAX_MESSAGES}"
fi
printf 'Report saved to: C:\\Users\\jim\\Downloads\\RTL-Windows-ADS-B-Tracker_Dump1090_Integrated_Runtime_Test.txt\n'
