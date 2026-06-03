#!/usr/bin/env bash
# Bounded live test for the application backend and ADS-B JSON proxy API.
# Intended environment: MSYS2 UCRT64.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${PROJECT_ROOT}/src/backend/rtl_windows_backend.py"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_API_Test.txt"
LOG="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_API_Test.log"
STATUS_JSON="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_status.json"
AIRCRAFT_JSON="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_aircraft.json"
UI_HTML="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_UI_index.html"
UI_JS="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_UI_app.js"
API_PORT=18090
DUMP_PORT=18180
OBSERVE_SECONDS=35
BACKEND_PID=''

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

stop_backend() {
    if [[ -n "${BACKEND_PID}" ]] && kill -0 "${BACKEND_PID}" 2>/dev/null; then
        curl -fsS -X POST "http://127.0.0.1:${API_PORT}/api/decoder/stop" >/dev/null 2>&1 || true
        kill -INT "${BACKEND_PID}" 2>/dev/null || true
        sleep 1
        kill -KILL "${BACKEND_PID}" 2>/dev/null || true
        wait "${BACKEND_PID}" 2>/dev/null || true
    fi
    BACKEND_PID=''
}
trap stop_backend EXIT

[[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Run from MSYS2 UCRT64."
[[ -f "${BACKEND}" ]] || fail "Backend source is missing."
for command_name in python3 curl; do
    command -v "${command_name}" >/dev/null 2>&1 || fail "${command_name} is missing."
done

mkdir -p "${OUT}"
rm -f "${REPORT}" "${LOG}" "${STATUS_JSON}" "${AIRCRAFT_JSON}" "${UI_HTML}" "${UI_JS}"
exec > >(tee "${REPORT}") 2>&1

printf 'RTL-Windows-ADS-B-Tracker backend API test - %s\n' "$(date -Is 2>/dev/null || date)"
printf 'Starting backend on port %s with internal Dump1090 HTTP port %s.\n' "${API_PORT}" "${DUMP_PORT}"

python3 "${BACKEND}" \
    --host 127.0.0.1 \
    --port "${API_PORT}" \
    --dump-http-port "${DUMP_PORT}" \
    --autostart >"${LOG}" 2>&1 &
BACKEND_PID=$!

READY=0
for attempt in $(seq 1 25); do
    if curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_JSON}" 2>/dev/null; then
        READY=1
        break
    fi
    if ! kill -0 "${BACKEND_PID}" 2>/dev/null; then
        break
    fi
    sleep 1
done

if [[ "${READY}" -ne 1 ]]; then
    sed -n '1,180p' "${LOG}" 2>/dev/null || true
    fail "Backend API did not become reachable."
fi

python3 - "${STATUS_JSON}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["ok"] is True
assert data["receiver_roles"]["adsb"]["serial"] == "00001090"
assert data["receiver_roles"]["audio"]["serial"] == "00000162"
assert data["decoder"]["running"] is True
assert data["decoder"]["json_ready"] is True
print("PASS: backend status reports stable receiver roles and a running JSON-ready decoder.")
print("Initial status:", json.dumps(data, indent=2))
PY

curl -fsS "http://127.0.0.1:${API_PORT}/" >"${UI_HTML}"
curl -fsS "http://127.0.0.1:${API_PORT}/static/app.js" >"${UI_JS}"
grep -q 'id="map"' "${UI_HTML}" || fail "Served UI page does not contain the map container."
grep -q '/api/aircraft' "${UI_JS}" || fail "Served UI JavaScript does not consume the application aircraft API."
grep -q 'function color' "${UI_JS}" || fail "Served UI JavaScript does not include altitude trail styling."
printf 'PASS: Backend serves live map assets that consume application API endpoints.\n'

MAX_MESSAGES=0
MAX_AIRCRAFT=0
for second in $(seq 1 "${OBSERVE_SECONDS}"); do
    curl -fsS "http://127.0.0.1:${API_PORT}/api/aircraft" >"${AIRCRAFT_JSON}"
    read -r MESSAGES AIRCRAFT < <(
        python3 - "${AIRCRAFT_JSON}" <<'PY' | tr -d '\r'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
rows = data.get("aircraft", [])
print(int(data.get("messages", 0)), len(rows))
PY
    )
    (( MESSAGES > MAX_MESSAGES )) && MAX_MESSAGES="${MESSAGES}" || true
    (( AIRCRAFT > MAX_AIRCRAFT )) && MAX_AIRCRAFT="${AIRCRAFT}" || true
    if (( second == 1 || second % 5 == 0 || AIRCRAFT > 0 )); then
        printf 'Second %s: proxied messages=%s aircraft=%s\n' "${second}" "${MESSAGES}" "${AIRCRAFT}"
    fi
    if (( MESSAGES > 0 && AIRCRAFT > 0 )); then
        break
    fi
    sleep 1
done

printf '\nMaximum proxied messages observed: %s\n' "${MAX_MESSAGES}"
printf 'Maximum proxied aircraft observed: %s\n' "${MAX_AIRCRAFT}"

if (( MAX_MESSAGES <= 0 )); then
    sed -n '1,220p' "${LOG}" || true
    fail "Backend was healthy but no ADS-B messages were reported in the observation window."
fi

printf '\nBackend log excerpt:\n'
sed -n '1,100p' "${LOG}" || true
printf '\nPASS: Backend API started the serial-resolved ADS-B decoder and proxied live JSON with %s message(s).\n' "${MAX_MESSAGES}"
printf 'Report saved to: C:\\Users\\jim\\Downloads\\RTL-Windows-ADS-B-Tracker_Backend_API_Test.txt\n'
