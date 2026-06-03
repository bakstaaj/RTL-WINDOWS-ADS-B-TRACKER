#!/usr/bin/env bash
# Validate UI contract and bounded survey transport while ADS-B remains active.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${PROJECT_ROOT}/src/backend/rtl_windows_backend.py"
PROBE="${PROJECT_ROOT}/dist/native-windows/rtl_dual_device_probe.exe"
CATALOG="${PROJECT_ROOT}/runtime/settings/faa_airband_catalog.json"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Browser_Airband_Survey_Scan_Test.txt"
LOG="${OUT}/RTL-Windows-ADS-B-Tracker_Browser_Airband_Survey_Scan_Test_backend.log"
STATUS_BEFORE="${OUT}/RTL-Windows-ADS-B-Tracker_Browser_Airband_Survey_Scan_status_before.json"
STATUS_AFTER="${OUT}/RTL-Windows-ADS-B-Tracker_Browser_Airband_Survey_Scan_status_after.json"
CHANNELS="${OUT}/RTL-Windows-ADS-B-Tracker_Browser_Airband_Survey_Scan_channels.json"
METRICS="${OUT}/RTL-Windows-ADS-B-Tracker_Browser_Airband_Survey_Scan_metrics.json"
UI_HTML="${OUT}/RTL-Windows-ADS-B-Tracker_Browser_Airband_Survey_Scan_index.html"
UI_JS="${OUT}/RTL-Windows-ADS-B-Tracker_Browser_Airband_Survey_Scan_app.js"
API_PORT=19690
DUMP_PORT=19780
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
rm -f "${REPORT}" "${LOG}" "${STATUS_BEFORE}" "${STATUS_AFTER}" "${CHANNELS}" "${METRICS}" "${UI_HTML}" "${UI_JS}"
exec > >(tee "${REPORT}") 2>&1

printf 'RTL-Windows-ADS-B-Tracker bounded browser Survey Scan validation - %s\n' "$(date -Is 2>/dev/null || date)"
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
grep -q 'id="run-airband-survey"' "${UI_HTML}" || fail "Browser UI lacks Run Survey Scan."
grep -q 'id="stop-airband-survey"' "${UI_HTML}" || fail "Browser UI lacks Stop Scan."
grep -q 'runAirbandSurvey' "${UI_JS}" || fail "Browser source lacks bounded survey operation."
grep -q 'Survey complete. Levels rank sampled AM audio only' "${UI_JS}" || fail "Browser source lacks non-detection interpretation boundary."
printf 'PASS: Browser assets expose bounded Survey Scan controls without activity-detection claims.\n'

curl -fsS "http://127.0.0.1:${API_PORT}/api/airband/channels?radius_miles=100&limit=60" >"${CHANNELS}"
python3 - "http://127.0.0.1:${API_PORT}" "${CHANNELS}" "${METRICS}" <<'PY'
from array import array
from io import BytesIO
from pathlib import Path
from urllib.request import Request, urlopen
import json, math, sys, wave

base, channels_path, metrics_path = sys.argv[1:]
data=json.load(open(channels_path,encoding="utf-8"))
selected=[]; seen=set()
for channel in data["channels"]:
    if channel["frequency_hz"] in seen:
        continue
    seen.add(channel["frequency_hz"]); selected.append(channel)
    if len(selected)==3:
        break
assert len(selected)==3
results=[]
for channel in selected:
    payload=json.dumps({"frequency_hz":channel["frequency_hz"],"serviced_facility":channel["serviced_facility"],"frequency_use":channel["frequency_use"]}).encode()
    with urlopen(Request(base+"/api/audio/airband/live/start", data=payload, headers={"Content-Type":"application/json"}, method="POST"), timeout=6) as response:
        started=json.loads(response.read().decode())
    assert started["running"] and started["profile"]["modulation"]=="am"
    sequence=0; frames=[]
    for _ in range(2):
        with urlopen(base+f"/api/audio/live/chunk.wav?after={sequence}", timeout=5) as response:
            sequence=int(response.headers["X-Audio-Sequence"])
            body=response.read()
        with wave.open(BytesIO(body),"rb") as wav:
            assert wav.getframerate()==24000
            frames.append(wav.readframes(wav.getnframes()))
    raw=b"".join(frames)
    samples=array("h"); samples.frombytes(raw)
    if sys.byteorder!="little": samples.byteswap()
    rms=math.sqrt(sum(v*v for v in samples)/len(samples))
    results.append({"frequency_mhz":channel["frequency_mhz"],"frequency_use":channel["frequency_use"],"rms_sample":round(rms,2)})
    with urlopen(Request(base+"/api/audio/live/stop", data=b"{}", headers={"Content-Type":"application/json"}, method="POST"), timeout=5) as response:
        response.read()
Path(metrics_path).write_text(json.dumps({"sample_count":len(results),"results":results},indent=2)+"\n",encoding="utf-8")
print("PASS: Existing AM API supplied bounded level-survey segments for three nearby channels.")
for result in sorted(results,key=lambda row: row["rms_sample"],reverse=True):
    print(f"  {result['frequency_mhz']:.3f} MHz  RMS {result['rms_sample']:.2f}  {result['frequency_use']}")
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
printf 'ADS-B messages before validation: %s\n' "${MESSAGES_BEFORE}"
printf 'ADS-B messages after validation:  %s\n' "${MESSAGES_AFTER}"
printf 'ADS-B increase during bounded Survey Scan transport validation: %s\n' "${DELTA}"
(( DELTA > 0 )) || fail "ADS-B messages did not increase during survey validation."
printf '\nPASS: Bounded browser Survey Scan baseline is transport-valid while ADS-B remains operational.\n'
