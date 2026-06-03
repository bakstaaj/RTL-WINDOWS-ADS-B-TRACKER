#!/usr/bin/env bash
# Validate ranked-result Listen UI wiring and existing FAA-selected live AM transport.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${PROJECT_ROOT}/src/backend/rtl_windows_backend.py"
PROBE="${PROJECT_ROOT}/dist/native-windows/rtl_dual_device_probe.exe"
CATALOG="${PROJECT_ROOT}/runtime/settings/faa_airband_catalog.json"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Survey_Review_Action_Test.txt"
LOG="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Survey_Review_Action_backend.log"
STATUS_BEFORE="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Survey_Review_Action_status_before.json"
STATUS_AFTER="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Survey_Review_Action_status_after.json"
CHANNELS="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Survey_Review_Action_channels.json"
REVIEW_METRICS="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Survey_Review_Action_metrics.json"
REVIEW_WAV="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Survey_Review_Action_120025.wav"
UI_HTML="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Survey_Review_Action_index.html"
UI_JS="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Survey_Review_Action_app.js"
API_PORT=20090
DUMP_PORT=20180
BACKEND_PID=''

fail(){ printf 'ERROR: %s\n' "$1" >&2; exit 1; }
stop_backend(){
    if [[ -n "${BACKEND_PID}" ]] && kill -0 "${BACKEND_PID}" 2>/dev/null; then
        curl -fsS -X POST "http://127.0.0.1:${API_PORT}/api/audio/live/stop" >/dev/null 2>&1 || true
        curl -fsS -X POST "http://127.0.0.1:${API_PORT}/api/decoder/stop" >/dev/null 2>&1 || true
        kill -INT "${BACKEND_PID}" 2>/dev/null || true
        sleep 1
        kill -KILL "${BACKEND_PID}" 2>/dev/null || true
        wait "${BACKEND_PID}" 2>/dev/null || true
    fi
}
trap stop_backend EXIT

[[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Run from MSYS2 UCRT64."
for command in python3 curl rtl_fm; do command -v "${command}" >/dev/null 2>&1 || fail "${command} is missing."; done
[[ -s "${BACKEND}" && -x "${PROBE}" && -s "${CATALOG}" ]] || fail "Required backend/probe/catalog is missing."
mkdir -p "${OUT}"
rm -f "${REPORT}" "${LOG}" "${STATUS_BEFORE}" "${STATUS_AFTER}" "${CHANNELS}" "${REVIEW_METRICS}" "${REVIEW_WAV}" "${UI_HTML}" "${UI_JS}"
exec > >(tee "${REPORT}") 2>&1

printf 'RTL-Windows-ADS-B-Tracker Survey-result Listen-action validation - %s\n' "$(date -Is 2>/dev/null || date)"
PROBE_JSON="$("${PROBE}" --json)" || fail "Receiver-role preflight failed; stop active SDR sessions and retry."
printf 'Preflight mapping: %s\n' "${PROBE_JSON}"

python3 "${BACKEND}" --host 127.0.0.1 --port "${API_PORT}" --dump-http-port "${DUMP_PORT}" \
    --airband-catalog-file "${CATALOG}" --autostart >"${LOG}" 2>&1 &
BACKEND_PID=$!
for attempt in $(seq 1 25); do
    if curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_BEFORE}" 2>/dev/null; then break; fi
    kill -0 "${BACKEND_PID}" 2>/dev/null || fail "Backend exited during startup."
    sleep 1
done
[[ -s "${STATUS_BEFORE}" ]] || fail "Backend did not become ready."

MESSAGES_BEFORE="$(python3 - "${STATUS_BEFORE}" <<'PY' | tr -d '\r'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["decoder"]["json_ready"] is True
assert d["receiver_roles"]["audio"]["serial"] == "00000162"
print(int(d["decoder"].get("messages",0)))
PY
)"

curl -fsS "http://127.0.0.1:${API_PORT}/" >"${UI_HTML}"
curl -fsS "http://127.0.0.1:${API_PORT}/static/app.js" >"${UI_JS}"
grep -q 'manual review' "${UI_HTML}" || fail "Browser Survey Scan description lacks manual review instruction."
grep -q 'survey-review-listen' "${UI_JS}" || fail "Survey result renderer lacks Listen review control."
grep -q 'startAirbandLive(item.channel)' "${UI_JS}" || fail "Survey result Listen action is not wired to validated FAA channel selection."
grep -q 'result.*Listen button for manual review' "${UI_JS}" || fail "Survey completion text lacks operator-review instruction."
printf 'PASS: Browser assets provide ranked-result Listen review actions with manual-only interpretation.\n'

curl -fsS "http://127.0.0.1:${API_PORT}/api/airband/channels?radius_miles=100&limit=200" >"${CHANNELS}"
python3 - "http://127.0.0.1:${API_PORT}" "${CHANNELS}" "${REVIEW_WAV}" "${REVIEW_METRICS}" <<'PY'
from array import array
from io import BytesIO
from pathlib import Path
from urllib.request import Request, urlopen
import json, math, sys, wave

base, channels_path, wav_path, metrics_path = sys.argv[1:]
data = json.load(open(channels_path, encoding="utf-8"))
candidates = [row for row in data["channels"] if row["frequency_hz"] == 120025000 and "AWOS" in row["frequency_use"].upper()]
assert candidates, "Nearby FAA list did not contain 120.025 MHz AWOS candidate."
channel = candidates[0]
payload = json.dumps({
    "frequency_hz": channel["frequency_hz"],
    "serviced_facility": channel["serviced_facility"],
    "frequency_use": channel["frequency_use"],
}).encode()
with urlopen(Request(base + "/api/audio/airband/live/start", data=payload, headers={"Content-Type":"application/json"}, method="POST"), timeout=6) as response:
    started = json.loads(response.read().decode())
assert started["running"] is True
assert started["profile"]["modulation"] == "am"
sequence = 0
frames = []
for _ in range(4):
    with urlopen(base + f"/api/audio/live/chunk.wav?after={sequence}", timeout=5) as response:
        sequence = int(response.headers["X-Audio-Sequence"])
        body = response.read()
    with wave.open(BytesIO(body), "rb") as segment:
        assert segment.getframerate() == 24000
        frames.append(segment.readframes(segment.getnframes()))
raw = b"".join(frames)
samples = array("h")
samples.frombytes(raw)
if sys.byteorder != "little":
    samples.byteswap()
rms = math.sqrt(sum(value * value for value in samples) / len(samples))
peak = max(abs(value) for value in samples)
with wave.open(wav_path, "wb") as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(24000)
    output.writeframes(raw)
metrics = {
    "frequency_mhz": channel["frequency_mhz"],
    "frequency_use": channel["frequency_use"],
    "serviced_facility": channel["serviced_facility"],
    "duration_seconds": round(len(samples) / 24000, 3),
    "rms_sample": round(rms, 2),
    "peak_abs_sample": peak,
}
Path(metrics_path).write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
print("PASS: Survey-review target opened existing FAA-selected AM listening transport.")
print(json.dumps(metrics))
with urlopen(Request(base + "/api/audio/live/stop", data=b"{}", headers={"Content-Type":"application/json"}, method="POST"), timeout=5) as response:
    response.read()
PY

curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_AFTER}"
MESSAGES_AFTER="$(python3 - "${STATUS_AFTER}" <<'PY' | tr -d '\r'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["decoder"]["json_ready"] is True
print(int(d["decoder"].get("messages",0)))
PY
)"
DELTA=$((MESSAGES_AFTER-MESSAGES_BEFORE))
printf 'ADS-B messages before manual result review: %s\n' "${MESSAGES_BEFORE}"
printf 'ADS-B messages after manual result review:  %s\n' "${MESSAGES_AFTER}"
printf 'ADS-B increase during Survey-result Listen validation: %s\n' "${DELTA}"
(( DELTA > 0 )) || fail "ADS-B messages did not increase during survey-result Listen validation."
printf '\nPASS: Survey-result Listen review action is transport-valid while ADS-B remains operational.\n'
printf 'Review WAV: C:\\Users\\jim\\Downloads\\RTL-Windows-ADS-B-Tracker_Airband_Survey_Review_Action_120025.wav\n'
