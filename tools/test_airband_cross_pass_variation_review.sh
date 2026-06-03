#!/usr/bin/env bash
# Validate variation-review browser contract and one bounded AM/ADS-B live workflow.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${PROJECT_ROOT}/src/backend/rtl_windows_backend.py"
PROBE="${PROJECT_ROOT}/dist/native-windows/rtl_dual_device_probe.exe"
CATALOG="${PROJECT_ROOT}/runtime/settings/faa_airband_catalog.json"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Cross_Pass_Variation_Live_Test.txt"
LOG="${OUT}/RTL-Windows-ADS-B-Tracker_Cross_Pass_Variation_backend.log"
STATUS_BEFORE="${OUT}/RTL-Windows-ADS-B-Tracker_Cross_Pass_Variation_status_before.json"
STATUS_AFTER="${OUT}/RTL-Windows-ADS-B-Tracker_Cross_Pass_Variation_status_after.json"
CHANNELS="${OUT}/RTL-Windows-ADS-B-Tracker_Cross_Pass_Variation_channels.json"
METRICS="${OUT}/RTL-Windows-ADS-B-Tracker_Cross_Pass_Variation_metrics.json"
UI_HTML="${OUT}/RTL-Windows-ADS-B-Tracker_Cross_Pass_Variation_index.html"
UI_JS="${OUT}/RTL-Windows-ADS-B-Tracker_Cross_Pass_Variation_app.js"
API_PORT=20890
DUMP_PORT=20980
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

printf 'RTL-Windows-ADS-B-Tracker cross-pass variation review live validation - %s\n' "$(date -Is 2>/dev/null || date)"
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
d=json.load(open(sys.argv[1],encoding="utf-8")); assert d["decoder"]["json_ready"] is True
assert d["receiver_roles"]["audio"]["serial"]=="00000162"
print(int(d["decoder"].get("messages",0)))
PY
)"
curl -fsS "http://127.0.0.1:${API_PORT}/" >"${UI_HTML}"
curl -fsS "http://127.0.0.1:${API_PORT}/static/app.js" >"${UI_JS}"
grep -q 'id="survey-variation-threshold"' "${UI_HTML}" || fail "UI lacks Variation mark selector."
grep -q '1.25 × pass low' "${UI_HTML}" || fail "UI lacks changing-level options."
grep -q 'not confirmed voice traffic' "${UI_HTML}" || fail "UI lacks observation-only boundary."
grep -q 'function surveyVariationRatio' "${UI_JS}" || fail "Browser lacks cross-pass ratio calculation."
grep -q 'rmsValues' "${UI_JS}" || fail "Browser does not retain per-pass measurements."
grep -q 'variation-changing' "${UI_JS}" || fail "Browser does not label changing-level observations."
grep -q 'not confirmed voice traffic' "${UI_JS}" || fail "Completion text lacks review-only boundary."
printf 'PASS: Browser exposes cross-pass variation marking with manual-review boundary.\n'

curl -fsS "http://127.0.0.1:${API_PORT}/api/airband/channels?radius_miles=100&limit=200" >"${CHANNELS}"
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
    use=(channel.get("frequency_use") or "").upper()
    category=(channel.get("category") or "").lower()
    if not (category in ("weather","atis") or any(t in use for t in ("AWOS","ASOS","ATIS"))): continue
    if channel["frequency_hz"] in seen: continue
    seen.add(channel["frequency_hz"]); selected.append(channel)
    if len(selected)==2: break
assert len(selected)==2, "Need two nearby Weather/ATIS records for variation validation."
PASSES=2
VARIATION_MARK=1.25
aggregate={row["frequency_hz"]:{"frequency_mhz":row["frequency_mhz"],"frequency_use":row["frequency_use"],"rms_values":[]} for row in selected}
for _ in range(PASSES):
    for channel in selected:
        body=json.dumps({"frequency_hz":channel["frequency_hz"],"serviced_facility":channel["serviced_facility"],"frequency_use":channel["frequency_use"]}).encode()
        with urlopen(Request(base+"/api/audio/airband/live/start",data=body,headers={"Content-Type":"application/json"},method="POST"),timeout=6) as response:
            started=json.loads(response.read().decode())
        assert started["running"] and started["profile"]["modulation"]=="am"
        sequence=0; raw=b""
        for _chunk in range(2):
            with urlopen(base+f"/api/audio/live/chunk.wav?after={sequence}",timeout=5) as response:
                sequence=int(response.headers["X-Audio-Sequence"]); segment=response.read()
            with wave.open(BytesIO(segment),"rb") as wav: raw += wav.readframes(wav.getnframes())
        samples=array("h"); samples.frombytes(raw)
        if sys.byteorder!="little": samples.byteswap()
        rms=math.sqrt(sum(v*v for v in samples)/len(samples))
        aggregate[channel["frequency_hz"]]["rms_values"].append(round(rms,2))
        with urlopen(Request(base+"/api/audio/live/stop",data=b"{}",headers={"Content-Type":"application/json"},method="POST"),timeout=5) as response: response.read()
results=[]
for value in aggregate.values():
    values=value["rms_values"]
    ratio=round(max(values)/max(1,min(values)),3)
    value["average_rms"]=round(sum(values)/len(values),2)
    value["variation_ratio"]=ratio
    value["changing_level"]=ratio>=VARIATION_MARK
    results.append(value)
payload={"passes":PASSES,"variation_mark_ratio":VARIATION_MARK,"results":results}
Path(metrics_path).write_text(json.dumps(payload,indent=2)+"\n",encoding="utf-8")
print("PASS: Cross-pass live measurements collected from two Weather/ATIS channels.")
for row in results: print(f"  {row['frequency_mhz']:.3f} MHz  RMS values {row['rms_values']}  variation {row['variation_ratio']:.3f}x  changing={row['changing_level']}  {row['frequency_use']}")
PY
curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_AFTER}"
MESSAGES_AFTER="$(python3 - "${STATUS_AFTER}" <<'PY' | tr -d '\r'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); assert d["decoder"]["json_ready"] is True
print(int(d["decoder"].get("messages",0)))
PY
)"
DELTA=$((MESSAGES_AFTER-MESSAGES_BEFORE))
printf 'ADS-B messages before variation validation: %s\n' "${MESSAGES_BEFORE}"
printf 'ADS-B messages after variation validation:  %s\n' "${MESSAGES_AFTER}"
printf 'ADS-B increase during variation validation: %s\n' "${DELTA}"
(( DELTA > 0 )) || fail "ADS-B messages did not increase during variation validation."
printf '\nPASS: Cross-pass variation review completed its single live validation while ADS-B remained operational.\n'
