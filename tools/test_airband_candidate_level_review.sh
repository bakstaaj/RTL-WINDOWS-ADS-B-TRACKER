#!/usr/bin/env bash
# Validate candidate-level browser contract and one bounded AM/ADS-B live workflow.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${PROJECT_ROOT}/src/backend/rtl_windows_backend.py"
PROBE="${PROJECT_ROOT}/dist/native-windows/rtl_dual_device_probe.exe"
CATALOG="${PROJECT_ROOT}/runtime/settings/faa_airband_catalog.json"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Candidate_Level_Review_Live_Test.txt"
LOG="${OUT}/RTL-Windows-ADS-B-Tracker_Candidate_Level_Review_backend.log"
STATUS_BEFORE="${OUT}/RTL-Windows-ADS-B-Tracker_Candidate_Level_Review_status_before.json"
STATUS_AFTER="${OUT}/RTL-Windows-ADS-B-Tracker_Candidate_Level_Review_status_after.json"
CHANNELS="${OUT}/RTL-Windows-ADS-B-Tracker_Candidate_Level_Review_channels.json"
METRICS="${OUT}/RTL-Windows-ADS-B-Tracker_Candidate_Level_Review_metrics.json"
UI_HTML="${OUT}/RTL-Windows-ADS-B-Tracker_Candidate_Level_Review_index.html"
UI_JS="${OUT}/RTL-Windows-ADS-B-Tracker_Candidate_Level_Review_app.js"
API_PORT=20490
DUMP_PORT=20580
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

printf 'RTL-Windows-ADS-B-Tracker candidate-level review live validation - %s\n' "$(date -Is 2>/dev/null || date)"
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
grep -q 'id="survey-candidate-threshold"' "${UI_HTML}" || fail "UI lacks Candidate level selector."
grep -q '1.25 × median' "${UI_HTML}" || fail "UI lacks median-relative candidate choices."
grep -q 'not confirmed voice traffic' "${UI_HTML}" || fail "UI lacks candidate interpretation boundary."
grep -q 'function surveyMedianRms' "${UI_JS}" || fail "Browser lacks median candidate calculation."
grep -q 'candidateMultiplier' "${UI_JS}" || fail "Browser does not apply selected candidate level."
grep -q 'candidate-above-level' "${UI_JS}" || fail "Browser does not label above-level candidates."
grep -q 'not confirmed voice traffic' "${UI_JS}" || fail "Completion text lacks candidate boundary."
printf 'PASS: Browser exposes relative candidate-level selection and manual-review boundary.\n'

curl -fsS "http://127.0.0.1:${API_PORT}/api/airband/channels?radius_miles=100&limit=200" >"${CHANNELS}"
python3 - "http://127.0.0.1:${API_PORT}" "${CHANNELS}" "${METRICS}" <<'PY'
from array import array
from io import BytesIO
from pathlib import Path
from statistics import median
from urllib.request import Request, urlopen
import json, math, sys, wave
base, channels_path, metrics_path = sys.argv[1:]
data=json.load(open(channels_path,encoding="utf-8"))
selected=[]; seen=set()
for channel in data["channels"]:
    use=(channel.get("frequency_use") or "").upper()
    category=(channel.get("category") or "").lower()
    suitable=category in ("weather","atis") or any(term in use for term in ("AWOS","ASOS","ATIS"))
    if not suitable or channel["frequency_hz"] in seen: continue
    seen.add(channel["frequency_hz"]); selected.append(channel)
    if len(selected)==2: break
assert len(selected)==2, "Need two nearby Weather/ATIS records for candidate validation."
results=[]
for channel in selected:
    body=json.dumps({"frequency_hz":channel["frequency_hz"],"serviced_facility":channel["serviced_facility"],"frequency_use":channel["frequency_use"]}).encode()
    with urlopen(Request(base+"/api/audio/airband/live/start",data=body,headers={"Content-Type":"application/json"},method="POST"),timeout=6) as response:
        started=json.loads(response.read().decode())
    assert started["running"] and started["profile"]["modulation"]=="am"
    sequence=0; raw=b""
    for _ in range(4):
        with urlopen(base+f"/api/audio/live/chunk.wav?after={sequence}",timeout=5) as response:
            sequence=int(response.headers["X-Audio-Sequence"]); segment=response.read()
        with wave.open(BytesIO(segment),"rb") as wav: raw += wav.readframes(wav.getnframes())
    samples=array("h"); samples.frombytes(raw)
    if sys.byteorder!="little": samples.byteswap()
    rms=math.sqrt(sum(value*value for value in samples)/len(samples))
    results.append({"frequency_mhz":channel["frequency_mhz"],"frequency_use":channel["frequency_use"],"rms_sample":round(rms,2)})
    with urlopen(Request(base+"/api/audio/live/stop",data=b"{}",headers={"Content-Type":"application/json"},method="POST"),timeout=5) as response: response.read()
baseline=median(row["rms_sample"] for row in results); threshold=round(baseline*1.25,2)
candidates=[row for row in results if row["rms_sample"]>=threshold]
payload={"rule":"1.25 x median RMS; measurement candidate only","median_rms_sample":round(baseline,2),"threshold_rms_sample":threshold,"candidates":candidates,"results":results}
Path(metrics_path).write_text(json.dumps(payload,indent=2)+"\n",encoding="utf-8")
print("PASS: Candidate-level live data collected from two Weather/ATIS channels.")
for row in results: print(f"  {row['frequency_mhz']:.3f} MHz  RMS {row['rms_sample']:.2f}  {row['frequency_use']}")
print(f"  Median={baseline:.2f}; 1.25x level={threshold:.2f}; above-level candidates={len(candidates)}")
PY
curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_AFTER}"
MESSAGES_AFTER="$(python3 - "${STATUS_AFTER}" <<'PY' | tr -d '\r'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); assert d["decoder"]["json_ready"] is True
print(int(d["decoder"].get("messages",0)))
PY
)"
DELTA=$((MESSAGES_AFTER-MESSAGES_BEFORE))
printf 'ADS-B messages before candidate-level validation: %s\n' "${MESSAGES_BEFORE}"
printf 'ADS-B messages after candidate-level validation:  %s\n' "${MESSAGES_AFTER}"
printf 'ADS-B increase during candidate-level validation: %s\n' "${DELTA}"
(( DELTA > 0 )) || fail "ADS-B messages did not increase during candidate-level validation."
printf '\nPASS: Candidate-level review completed its single live validation while ADS-B remained operational.\n'
