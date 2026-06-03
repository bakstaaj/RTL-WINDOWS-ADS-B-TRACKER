#!/usr/bin/env bash
# Bounded test for rolling live NOAA WAV chunks while ADS-B remains active.
# Intended environment: MSYS2 UCRT64.

set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${PROJECT_ROOT}/src/backend/rtl_windows_backend.py"
PROBE="${PROJECT_ROOT}/dist/native-windows/rtl_dual_device_probe.exe"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Live_NOAA_API_Test.txt"
LOG="${OUT}/RTL-Windows-ADS-B-Tracker_Live_NOAA_API_Test.log"
STATUS_BEFORE="${OUT}/RTL-Windows-ADS-B-Tracker_Live_NOAA_status_before.json"
STATUS_AFTER="${OUT}/RTL-Windows-ADS-B-Tracker_Live_NOAA_status_after.json"
LIVE_WAV="${OUT}/RTL-Windows-ADS-B-Tracker_Live_NOAA_API_Test.wav"
LIVE_METRICS="${OUT}/RTL-Windows-ADS-B-Tracker_Live_NOAA_API_Test_metrics.json"
API_PORT=18690
DUMP_PORT=18780
BACKEND_PID=''

fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
stop_backend() {
    if [[ -n "${BACKEND_PID}" ]] && kill -0 "${BACKEND_PID}" 2>/dev/null; then
        curl -fsS -X POST "http://127.0.0.1:${API_PORT}/api/audio/live/stop" >/dev/null 2>&1 || true
        curl -fsS -X POST "http://127.0.0.1:${API_PORT}/api/audio/stop" >/dev/null 2>&1 || true
        curl -fsS -X POST "http://127.0.0.1:${API_PORT}/api/decoder/stop" >/dev/null 2>&1 || true
        kill -INT "${BACKEND_PID}" 2>/dev/null || true
        sleep 1
        kill -KILL "${BACKEND_PID}" 2>/dev/null || true
        wait "${BACKEND_PID}" 2>/dev/null || true
    fi
}
trap stop_backend EXIT

[[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Run from MSYS2 UCRT64."
for cmd in python3 curl rtl_fm; do command -v "${cmd}" >/dev/null 2>&1 || fail "${cmd} is missing."; done
[[ -s "${BACKEND}" && -x "${PROBE}" ]] || fail "Required backend/probe runtime is missing."
mkdir -p "${OUT}"
rm -f "${REPORT}" "${LOG}" "${STATUS_BEFORE}" "${STATUS_AFTER}" "${LIVE_WAV}" "${LIVE_METRICS}"
exec > >(tee "${REPORT}") 2>&1

printf 'RTL-Windows-ADS-B-Tracker live NOAA API test - %s\n' "$(date -Is 2>/dev/null || date)"
PROBE_JSON="$("${PROBE}" --json)" || fail "Receiver-role probe failed; stop active SDR sessions and retry."
printf 'Preflight mapping: %s\n' "${PROBE_JSON}"

python3 "${BACKEND}" --host 127.0.0.1 --port "${API_PORT}" --dump-http-port "${DUMP_PORT}" --autostart >"${LOG}" 2>&1 &
BACKEND_PID=$!
for attempt in $(seq 1 25); do
    if curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_BEFORE}" 2>/dev/null; then break; fi
    kill -0 "${BACKEND_PID}" 2>/dev/null || fail "Backend exited during startup."
    sleep 1
done
[[ -s "${STATUS_BEFORE}" ]] || fail "Backend API did not become ready."
MESSAGES_BEFORE="$(python3 - "${STATUS_BEFORE}" <<'PY' | tr -d '\r'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["decoder"]["json_ready"] and d["receiver_roles"]["audio"]["serial"]=="00000162"
print(int(d["decoder"].get("messages",0)))
PY
)"
printf 'ADS-B messages before live NOAA start: %s\n' "${MESSAGES_BEFORE}"

curl -fsS -X POST "http://127.0.0.1:${API_PORT}/api/audio/noaa/live/start" |
python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["running"] is True; assert d["audio_role"]["serial"]=="00000162"; print("PASS: Live NOAA mode started on cached audio role.", d["audio_role"])'

python3 - "http://127.0.0.1:${API_PORT}" "${LIVE_WAV}" "${LIVE_METRICS}" <<'PY'
from array import array
from io import BytesIO
from pathlib import Path
from urllib.request import urlopen
import json, math, sys, time, wave

base, output_path, metrics_path = sys.argv[1:]
sequence = 0
frames = []
received = []
started = time.monotonic()
while len(frames) < 10 and time.monotonic() - started < 12:
    with urlopen(f"{base}/api/audio/live/chunk.wav?after={sequence}", timeout=4) as response:
        if response.status == 204:
            continue
        next_sequence = int(response.headers["X-Audio-Sequence"])
        payload = response.read()
    with wave.open(BytesIO(payload), "rb") as part:
        assert part.getnchannels() == 1
        assert part.getframerate() == 24000
        pcm = part.readframes(part.getnframes())
        duration = part.getnframes() / part.getframerate()
    assert next_sequence > sequence
    sequence = next_sequence
    frames.append(pcm)
    received.append({"sequence": sequence, "duration_seconds": round(duration, 3)})
raw = b"".join(frames)
if len(frames) < 8:
    raise SystemExit(f"Received only {len(frames)} live WAV chunks.")
samples = array("h")
samples.frombytes(raw)
if sys.byteorder != "little":
    samples.byteswap()
peak = max(abs(x) for x in samples)
rms = math.sqrt(sum(x*x for x in samples) / len(samples))
clipped = sum(1 for x in samples if abs(x)>=32760) * 100.0 / len(samples)
with wave.open(output_path, "wb") as wav:
    wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(24000); wav.writeframes(raw)
metrics = {"chunks_received":len(frames),"sequences":received,"duration_seconds":round(len(samples)/24000,3),"peak_abs_sample":peak,"rms_sample":round(rms,2),"clipped_percent":round(clipped,6)}
Path(metrics_path).write_text(json.dumps(metrics,indent=2)+"\n",encoding="utf-8")
print("PASS: Rolling live WAV chunks decoded and combined:", json.dumps(metrics))
PY

curl -fsS -X POST "http://127.0.0.1:${API_PORT}/api/audio/live/stop" >/dev/null
curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_AFTER}"
MESSAGES_AFTER="$(python3 - "${STATUS_AFTER}" <<'PY' | tr -d '\r'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["decoder"]["json_ready"]
print(int(d["decoder"].get("messages",0)))
PY
)"
DELTA=$((MESSAGES_AFTER - MESSAGES_BEFORE))
printf 'ADS-B messages after live NOAA: %s\n' "${MESSAGES_AFTER}"
printf 'ADS-B increase during live NOAA API test: %s\n' "${DELTA}"
(( DELTA > 0 )) || fail "ADS-B messages did not increase during live NOAA API test."
printf '\nBackend log excerpt:\n'
sed -n '1,140p' "${LOG}" || true
printf '\nPASS: Live NOAA API delivered rolling audio chunks while ADS-B remained operational.\n'
printf 'Review WAV: C:\\Users\\jim\\Downloads\\RTL-Windows-ADS-B-Tracker_Live_NOAA_API_Test.wav\n'
