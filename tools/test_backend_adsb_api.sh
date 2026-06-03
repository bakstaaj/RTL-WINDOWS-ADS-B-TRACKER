#!/usr/bin/env bash
# Bounded live test for application backend, map assets, ADS-B proxy and NOAA recording.
# Intended environment: MSYS2 UCRT64.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${PROJECT_ROOT}/src/backend/rtl_windows_backend.py"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_API_Test.txt"
LOG="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_API_Test.log"
STATUS_JSON="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_status.json"
AIRCRAFT_JSON="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_aircraft.json"
AUDIO_STATUS="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_audio_status.json"
AUDIO_WAV="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_NOAA_test.wav"
UI_HTML="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_UI_index.html"
UI_JS="${OUT}/RTL-Windows-ADS-B-Tracker_Backend_UI_app.js"

API_PORT=18090
DUMP_PORT=18180
ADSB_OBSERVE_SECONDS=30
AUDIO_RECORD_SECONDS=8
BACKEND_PID=''

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

stop_backend() {
    if [[ -n "${BACKEND_PID}" ]] && kill -0 "${BACKEND_PID}" 2>/dev/null; then
        curl -fsS -X POST "http://127.0.0.1:${API_PORT}/api/audio/stop" >/dev/null 2>&1 || true
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
for cmd in python3 curl rtl_fm; do
    command -v "${cmd}" >/dev/null 2>&1 || fail "${cmd} is missing."
done

mkdir -p "${OUT}"
rm -f "${REPORT}" "${LOG}" "${STATUS_JSON}" "${AIRCRAFT_JSON}" \
      "${AUDIO_STATUS}" "${AUDIO_WAV}" "${UI_HTML}" "${UI_JS}"
exec > >(tee "${REPORT}") 2>&1

printf 'RTL-Windows-ADS-B-Tracker backend ADS-B/NOAA API test - %s\n' "$(date -Is 2>/dev/null || date)"
printf 'Starting backend on port %s; internal Dump1090 port %s; NOAA test recording %s seconds.\n' \
    "${API_PORT}" "${DUMP_PORT}" "${AUDIO_RECORD_SECONDS}"

python3 "${BACKEND}" \
    --host 127.0.0.1 \
    --port "${API_PORT}" \
    --dump-http-port "${DUMP_PORT}" \
    --audio-record-seconds "${AUDIO_RECORD_SECONDS}" \
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
assert data["receiver_location"]["latitude"] == 38.7467
print("PASS: backend status reports stable receiver roles and a running JSON-ready ADS-B decoder.")
print("Initial role mapping:", data["receiver_roles"])
PY

curl -fsS "http://127.0.0.1:${API_PORT}/" >"${UI_HTML}"
curl -fsS "http://127.0.0.1:${API_PORT}/static/app.js" >"${UI_JS}"
grep -q 'id="map"' "${UI_HTML}" || fail "Served UI page does not contain the map container."
grep -q 'id="record-noaa"' "${UI_HTML}" || fail "Served UI page does not contain NOAA recording controls."
grep -q '/api/aircraft' "${UI_JS}" || fail "Served UI JavaScript does not consume the aircraft API."
grep -q '/api/audio/status' "${UI_JS}" || fail "Served UI JavaScript does not consume the audio API."
printf 'PASS: backend serves browser map and NOAA-control assets through application endpoints.\n'

MAX_MESSAGES=0
MAX_AIRCRAFT=0
for second in $(seq 1 "${ADSB_OBSERVE_SECONDS}"); do
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
        printf 'ADS-B second %s: messages=%s aircraft=%s\n' "${second}" "${MESSAGES}" "${AIRCRAFT}"
    fi
    if (( MESSAGES > 0 )); then
        break
    fi
    sleep 1
done
(( MAX_MESSAGES > 0 )) || fail "Backend was healthy but no ADS-B messages were reported before NOAA recording."
printf 'PASS: ADS-B API reported %s message(s) before NOAA recording.\n' "${MAX_MESSAGES}"

curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_JSON}"
MESSAGES_BEFORE_AUDIO="$(
    python3 - "${STATUS_JSON}" <<'PY' | tr -d '\r'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["decoder"]["json_ready"] is True
print(int(data["decoder"].get("messages", 0)))
PY
)"

printf '\nStarting backend-managed NOAA recording while ADS-B remains active...\n'
curl -fsS -X POST "http://127.0.0.1:${API_PORT}/api/audio/noaa/start" >"${AUDIO_STATUS}"
python3 - "${AUDIO_STATUS}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["running"] is True
assert data["audio_role"]["serial"] == "00000162"
print("PASS: NOAA recording started on cached dedicated audio role:", data["audio_role"])
PY

AUDIO_READY=0
for attempt in $(seq 1 20); do
    curl -fsS "http://127.0.0.1:${API_PORT}/api/audio/status" >"${AUDIO_STATUS}"
    if python3 - "${AUDIO_STATUS}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
raise SystemExit(0 if (not data["running"] and data["recording_ready"]) else 1)
PY
    then
        AUDIO_READY=1
        break
    fi
    sleep 1
done
(( AUDIO_READY == 1 )) || fail "Backend-managed NOAA WAV was not finalized in the expected interval."

curl -fsS "http://127.0.0.1:${API_PORT}/api/audio/latest.wav" >"${AUDIO_WAV}"
python3 - "${AUDIO_STATUS}" "${AUDIO_WAV}" <<'PY'
import json, sys, wave
from pathlib import Path
status = json.load(open(sys.argv[1], encoding="utf-8"))
metrics = status["metrics"]
assert metrics["duration_seconds"] >= 6.0
assert metrics["sample_rate_hz"] == 24000
assert metrics["peak_abs_sample"] > 0
assert metrics["clipped_percent"] < 1.0
with wave.open(str(Path(sys.argv[2])), "rb") as wav:
    assert wav.getnchannels() == 1
    assert wav.getframerate() == 24000
    assert wav.getnframes() > 24000 * 6
print("PASS: NOAA WAV endpoint returned valid audio:", json.dumps(metrics))
PY

curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_JSON}"
MESSAGES_AFTER_AUDIO="$(
    python3 - "${STATUS_JSON}" <<'PY' | tr -d '\r'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["decoder"]["json_ready"] is True
print(int(data["decoder"].get("messages", 0)))
PY
)"
AUDIO_MESSAGE_DELTA=$((MESSAGES_AFTER_AUDIO - MESSAGES_BEFORE_AUDIO))
printf 'ADS-B messages before NOAA recording: %s\n' "${MESSAGES_BEFORE_AUDIO}"
printf 'ADS-B messages after NOAA recording:  %s\n' "${MESSAGES_AFTER_AUDIO}"
printf 'ADS-B message increase during backend-managed NOAA recording: %s\n' "${AUDIO_MESSAGE_DELTA}"
(( AUDIO_MESSAGE_DELTA > 0 )) || fail "ADS-B messages did not increase while backend-managed NOAA recording ran."

printf '\nBackend log excerpt:\n'
sed -n '1,140p' "${LOG}" || true
printf '\nPASS: Backend APIs sustained ADS-B decoding and returned a valid NOAA WAV recording.\n'
printf 'Report saved to: C:\\Users\\jim\\Downloads\\RTL-Windows-ADS-B-Tracker_Backend_API_Test.txt\n'
printf 'Test WAV saved to: C:\\Users\\jim\\Downloads\\RTL-Windows-ADS-B-Tracker_Backend_NOAA_test.wav\n'
