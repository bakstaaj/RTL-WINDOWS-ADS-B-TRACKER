#!/usr/bin/env bash
# Validate Capture 10s UI wiring and existing FAA-selected live AM transport.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${PROJECT_ROOT}/src/backend/rtl_windows_backend.py"
PROBE="${PROJECT_ROOT}/dist/native-windows/rtl_dual_device_probe.exe"
CATALOG="${PROJECT_ROOT}/runtime/settings/faa_airband_catalog.json"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Capture_Review_Action_Test.txt"
LOG="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Capture_Review_Action_backend.log"
STATUS_BEFORE="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Capture_Review_Action_status_before.json"
STATUS_AFTER="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Capture_Review_Action_status_after.json"
CHANNELS="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Capture_Review_Action_channels.json"
CAPTURE_METRICS="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Capture_Review_Action_metrics.json"
CAPTURE_WAV="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Capture_Review_Action_120025.wav"
UI_HTML="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Capture_Review_Action_index.html"
UI_JS="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Capture_Review_Action_app.js"
API_PORT=20290
DUMP_PORT=20380
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
rm -f "${REPORT}" "${LOG}" "${STATUS_BEFORE}" "${STATUS_AFTER}" "${CHANNELS}" "${CAPTURE_METRICS}" "${CAPTURE_WAV}" "${UI_HTML}" "${UI_JS}"
exec > >(tee "${REPORT}") 2>&1

printf 'RTL-Windows-ADS-B-Tracker bounded Airband Capture review validation - %s\n' "$(date -Is 2>/dev/null || date)"
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
grep -q 'Capture 10s' "${UI_HTML}" || fail "Browser airband description lacks Capture 10s action."
grep -q 'captureAirbandSample(channel)' "${UI_JS}" || fail "Nearby channel rows are not wired to Capture 10s."
grep -q 'captureAirbandSample(item.channel)' "${UI_JS}" || fail "Survey result rows are not wired to Capture 10s."
grep -q 'function encodeMonoPcmWav' "${UI_JS}" || fail "Browser capture lacks WAV assembly implementation."
grep -q 'airbandCaptureFilename' "${UI_JS}" || fail "Browser capture lacks labeled WAV download naming."
grep -q 'does not identify active voice traffic' "${UI_HTML}" || fail "Capture UI no longer retains measurement-only boundary."
printf 'PASS: Browser assets provide manual Capture 10s actions on channel and survey-result rows.\n'

curl -fsS "http://127.0.0.1:${API_PORT}/api/airband/channels?radius_miles=100&limit=200" >"${CHANNELS}"
python3 - "http://127.0.0.1:${API_PORT}" "${CHANNELS}" "${CAPTURE_WAV}" "${CAPTURE_METRICS}" <<'PY'
from array import array
from io import BytesIO
from pathlib import Path
from urllib.request import Request, urlopen
import json, math, sys, wave

base, channels_path, wav_path, metrics_path = sys.argv[1:]
data = json.load(open(channels_path, encoding="utf-8"))
rows = [row for row in data["channels"] if row["frequency_hz"] == 120025000 and "AWOS" in row["frequency_use"].upper()]
assert rows, "Nearby FAA list did not contain established AWOS capture candidate."
channel = rows[0]
payload = json.dumps({"frequency_hz": channel["frequency_hz"], "serviced_facility": channel["serviced_facility"], "frequency_use": channel["frequency_use"]}).encode()
with urlopen(Request(base + "/api/audio/airband/live/start", data=payload, headers={"Content-Type":"application/json"}, method="POST"), timeout=6) as response:
    started = json.loads(response.read().decode())
assert started["running"] and started["profile"]["modulation"] == "am"
sequence = 0
frames = []
for _ in range(8):
    with urlopen(base + f"/api/audio/live/chunk.wav?after={sequence}", timeout=5) as response:
        sequence = int(response.headers["X-Audio-Sequence"])
        body = response.read()
    with wave.open(BytesIO(body), "rb") as part:
        assert part.getnchannels() == 1 and part.getframerate() == 24000
        frames.append(part.readframes(part.getnframes()))
raw = b"".join(frames)
samples = array("h"); samples.frombytes(raw)
if sys.byteorder != "little": samples.byteswap()
rms = math.sqrt(sum(value * value for value in samples) / len(samples))
peak = max(abs(value) for value in samples)
clipped = sum(1 for value in samples if abs(value) >= 32760) * 100.0 / len(samples)
with wave.open(wav_path, "wb") as output:
    output.setnchannels(1); output.setsampwidth(2); output.setframerate(24000); output.writeframes(raw)
metrics = {"frequency_mhz":channel["frequency_mhz"],"frequency_use":channel["frequency_use"],"facility":channel["serviced_facility"],"duration_seconds":round(len(samples)/24000,3),"rms_sample":round(rms,2),"peak_abs_sample":peak,"clipped_percent":round(clipped,6)}
Path(metrics_path).write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
print("PASS: Existing AM transport delivered bounded capture-review WAV material.")
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
printf 'ADS-B messages before bounded capture: %s\n' "${MESSAGES_BEFORE}"
printf 'ADS-B messages after bounded capture:  %s\n' "${MESSAGES_AFTER}"
printf 'ADS-B increase during bounded Capture review validation: %s\n' "${DELTA}"
(( DELTA > 0 )) || fail "ADS-B messages did not increase during bounded capture validation."
printf '\nPASS: Bounded Airband Capture review is transport-valid while ADS-B remains operational.\n'
printf 'Review WAV: C:\\Users\\jim\\Downloads\\RTL-Windows-ADS-B-Tracker_Airband_Capture_Review_Action_120025.wav\n'
