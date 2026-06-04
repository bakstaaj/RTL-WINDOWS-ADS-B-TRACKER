#!/usr/bin/env bash
# RTL ADS-B Tracker Windows Service release builder
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-v0.1.0-rc1}"
DOWNLOADS='/c/Users/jim/Downloads'
NAME="RTL-ADS-B-Tracker-Windows-Service-${VERSION}"
BUILD="${ROOT}/runtime/build/windows-service"
STAGE="${BUILD}/${NAME}"
ZIP_OUT="${DOWNLOADS}/${NAME}.zip"
BACKEND_EXE='RTLADSBTrackerBackend.exe'
SERVICE_EXE='RTLADSBTrackerService.exe'
WINSW_VERSION='v2.12.0'
WINSW_URL="https://github.com/winsw/winsw/releases/download/${WINSW_VERSION}/WinSW-x64.exe"
WINSW_LICENSE_URL="https://raw.githubusercontent.com/winsw/winsw/${WINSW_VERSION}/LICENSE.txt"

section(){ printf '\n====================================================================\n%s\n====================================================================\n' "$1"; }
fail(){ printf '\nERROR: %s\n' "$1" >&2; exit 1; }
winpath(){ cygpath -w "$1"; }

NATIVE_PYTHON_EXE=''
PYTHON_CMD=()

probe_native_python(){
  local out
  local -a candidate=("$@")
  [[ ${#candidate[@]} -gt 0 ]] || return 1

  out="$("${candidate[@]}" -c 'import os, sys
exe = sys.executable.replace("\\", "/")
low = exe.lower()
bad = ("/msys64/", "/ucrt64/", "/mingw64/", "/cygwin64/")
assert os.name == "nt", "not native Windows Python"
assert sys.version_info >= (3, 10), "Python 3.10+ required"
assert not any(x in low for x in bad), "MSYS2/Cygwin Python is not suitable for PyInstaller service release builds"
print(sys.executable)
' 2>/dev/null)" || return 1

  [[ -n "${out}" ]] || return 1
  PYTHON_CMD=("${candidate[@]}")
  NATIVE_PYTHON_EXE="${out}"
  return 0
}

try_python_glob(){
  local pattern="$1"
  local candidate
  while IFS= read -r candidate; do
    [[ -f "${candidate}" ]] || continue
    if probe_native_python "${candidate}"; then
      return 0
    fi
  done < <(compgen -G "${pattern}" || true)
  return 1
}

find_native_python(){
  local windows_user
  windows_user="${USERNAME:-${USER:-}}"

  # Prefer the official Windows launcher when available.
  if command -v py >/dev/null 2>&1 && probe_native_python py -3; then return 0; fi
  if command -v py.exe >/dev/null 2>&1 && probe_native_python py.exe -3; then return 0; fi

  # Try common python.org locations before PATH, because MSYS2 often shadows python.exe.
  try_python_glob "/c/Users/${windows_user}/AppData/Local/Programs/Python/Python*/python.exe" && return 0
  try_python_glob "/c/Python*/python.exe" && return 0
  try_python_glob "/c/Program Files/Python*/python.exe" && return 0
  try_python_glob "/c/Program Files (x86)/Python*/python.exe" && return 0

  # Try PATH last. probe_native_python rejects MSYS2/Cygwin Python.
  if command -v python.exe >/dev/null 2>&1 && probe_native_python python.exe; then return 0; fi
  if command -v python >/dev/null 2>&1 && probe_native_python python; then return 0; fi
  if command -v python3.exe >/dev/null 2>&1 && probe_native_python python3.exe; then return 0; fi

  return 1
}

copy_tree_required(){
  [[ -d "$1" ]] || fail "Required runtime directory is missing: $1"
  mkdir -p "$2"
  cp -R "$1"/. "$2"/
}

copy_dependency_dlls(){
  local executable="$1" destination="$2" dependency
  command -v ldd >/dev/null 2>&1 || return 0
  while IFS= read -r dependency; do
    [[ -f "${dependency}" ]] || continue
    case "${dependency,,}" in
      /c/windows/*|/windows/*) ;;
      *.dll) cp -n "${dependency}" "${destination}/" 2>/dev/null || true ;;
    esac
  done < <(ldd "${executable}" 2>/dev/null | awk '/=>/ {print $3}' | tr -d '\r')
}

cd "${ROOT}"
[[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Run the release builder from MSYS2 UCRT64."
for cmd in cygpath curl zip ldd; do
  command -v "${cmd}" >/dev/null 2>&1 || fail "${cmd} is missing."
done

section "Locate native Windows Python"
find_native_python || fail "Native Windows Python 3.10+ is required for the release build. Install Python for Windows with: winget install -e --id Python.Python.3.12"
printf 'Using native Python: %s\n' "${NATIVE_PYTHON_EXE}"

[[ -f 'src/backend/rtl_windows_pi_port_backend.py' && -f 'src/backend/rtl_windows_backend.py' && -f 'web/index.html' ]] ||
  fail "Application source is incomplete."
[[ -f 'dist/native-windows/rtl_dual_device_probe.exe' ]] ||
  fail "Build the device probe first: ./tools/build_native_device_probe.sh"
[[ -f 'dist/third_party/dump1090/dump1090.exe' && -f 'dist/third_party/dump1090/airport-codes.csv' ]] ||
  fail "Build Dump1090 first: ./tools/build_dump1090_windows.sh"
[[ -f 'runtime/settings/faa_airband_catalog.json' ]] ||
  fail "Import the FAA airband catalog first: ./tools/import_faa_airband_catalog.sh"

RTL_FM="$(command -v rtl_fm.exe || command -v rtl_fm || true)"
RTL_POWER="$(command -v rtl_power.exe || command -v rtl_power || true)"
[[ -n "${RTL_FM}" && -f "${RTL_FM}" ]] || fail "rtl_fm.exe is not available in PATH."
[[ -n "${RTL_POWER}" && -f "${RTL_POWER}" ]] || fail "rtl_power.exe is not available in PATH."

section "Build native Windows backend executable with PyInstaller"
rm -rf "${BUILD}"
mkdir -p "${BUILD}" "${DOWNLOADS}"
VENV="${BUILD}/pyinstaller-venv"

"${PYTHON_CMD[@]}" -m venv "$(winpath "${VENV}")"

if [[ -f "${VENV}/Scripts/python.exe" ]]; then
  VENV_PY="${VENV}/Scripts/python.exe"
elif [[ -f "${VENV}/bin/python.exe" ]]; then
  VENV_PY="${VENV}/bin/python.exe"
else
  printf 'Virtualenv contents:\n' >&2
  find "${VENV}" -maxdepth 3 -type f \( -name 'python.exe' -o -name 'python' \) -print >&2 || true
  fail "Native Python venv was created, but no usable python.exe was found under ${VENV}."
fi

printf 'Using build venv Python: %s\n' "${VENV_PY}"
"${VENV_PY}" -m pip install --disable-pip-version-check --quiet --upgrade pip pyinstaller

"${VENV_PY}" -m PyInstaller --noconfirm --clean --onedir --console \
  --name RTLADSBTrackerBackend \
  --paths "$(winpath "${ROOT}/src/backend")" \
  --distpath "$(winpath "${BUILD}/pyinstaller-dist")" \
  --workpath "$(winpath "${BUILD}/pyinstaller-work")" \
  --specpath "$(winpath "${BUILD}")" \
  "$(winpath "${ROOT}/src/backend/rtl_windows_pi_port_backend.py")"

[[ -f "${BUILD}/pyinstaller-dist/RTLADSBTrackerBackend/${BACKEND_EXE}" ]] ||
  fail "PyInstaller did not create ${BACKEND_EXE}."

section "Assemble service release layout"
mkdir -p "${STAGE}/app/backend" "${STAGE}/bin" "${STAGE}/notices" "${STAGE}/seed/settings"
cp -R "${BUILD}/pyinstaller-dist/RTLADSBTrackerBackend/." "${STAGE}/app/backend/"
copy_tree_required "${ROOT}/web" "${STAGE}/web"
copy_tree_required "${ROOT}/dist/native-windows" "${STAGE}/dist/native-windows"
copy_tree_required "${ROOT}/dist/third_party/dump1090" "${STAGE}/dist/third_party/dump1090"
cp "${RTL_FM}" "${STAGE}/bin/rtl_fm.exe"
cp "${RTL_POWER}" "${STAGE}/bin/rtl_power.exe"
copy_dependency_dlls "${RTL_FM}" "${STAGE}/bin"
copy_dependency_dlls "${RTL_POWER}" "${STAGE}/bin"
copy_dependency_dlls "${ROOT}/dist/native-windows/rtl_dual_device_probe.exe" "${STAGE}/bin"
copy_dependency_dlls "${ROOT}/dist/third_party/dump1090/dump1090.exe" "${STAGE}/bin"
cp "${ROOT}/runtime/settings/faa_airband_catalog.json" "${STAGE}/seed/settings/faa_airband_catalog.json"
cp "${ROOT}/docs/WINDOWS_SERVICE_RELEASE.md" "${STAGE}/README_SERVICE_RELEASE.md"

section "Download stable WinSW service executable and attribution"
curl -fL --retry 2 --connect-timeout 15 -o "${STAGE}/${SERVICE_EXE}" "${WINSW_URL}" ||
  fail "Could not download stable WinSW executable."
curl -fL --retry 2 --connect-timeout 15 -o "${STAGE}/notices/WinSW-LICENSE.txt" "${WINSW_LICENSE_URL}" ||
  fail "Could not download the WinSW license."

cat > "${STAGE}/notices/THIRD-PARTY-NOTICE.txt" <<NOTICE
RTL ADS-B Tracker Windows Service release includes WinSW ${WINSW_VERSION}.
WinSW wraps and manages the packaged backend as a Windows Service.
Source project: https://github.com/winsw/winsw
License: MIT; see WinSW-LICENSE.txt.
NOTICE

cat > "${STAGE}/RTLADSBTrackerService.xml" <<'XML'
<service>
  <id>RTLADSBTracker</id>
  <name>RTL ADS-B Tracker</name>
  <description>RTL-SDR ADS-B aircraft tracker with NOAA Weather and Airband audio services.</description>
  <executable>%BASE%\app\backend\RTLADSBTrackerBackend.exe</executable>
  <arguments>--host 127.0.0.1 --port 8090 --dump-http-port 18080 --log-file "%ProgramData%\RTL ADS-B Tracker\logs\backend.log" --log-level INFO --autostart</arguments>
  <workingdirectory>%BASE%</workingdirectory>
  <env name="RTL_ADSB_TRACKER_ROOT" value="%BASE%"/>
  <env name="RTL_ADSB_TRACKER_RUNTIME" value="%ProgramData%\RTL ADS-B Tracker\runtime"/>
  <env name="PATH" value="%BASE%\bin;%BASE%\dist\native-windows;%BASE%\dist\third_party\dump1090;%PATH%"/>
  <startmode>Automatic</startmode>
  <delayedAutoStart>true</delayedAutoStart>
  <onfailure action="restart" delay="10 sec"/>
  <onfailure action="restart" delay="30 sec"/>
  <logpath>%ProgramData%\RTL ADS-B Tracker\logs\service</logpath>
  <log mode="roll"></log>
  <stoptimeout>15000</stoptimeout>
</service>
XML

cat > "${STAGE}/install_service.cmd" <<'CMD'
@echo off
setlocal
cd /d "%~dp0"
net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
  echo ERROR: Run install_service.cmd from an Administrator Command Prompt.
  exit /b 1
)
set "DATA=%ProgramData%\RTL ADS-B Tracker"
if not exist "%DATA%\runtime\settings" mkdir "%DATA%\runtime\settings"
if not exist "%DATA%\logs\service" mkdir "%DATA%\logs\service"
if not exist "%DATA%\runtime\settings\faa_airband_catalog.json" (
  copy /Y "%~dp0seed\settings\faa_airband_catalog.json" "%DATA%\runtime\settings\faa_airband_catalog.json" >nul
)
"%~dp0RTLADSBTrackerService.exe" install
if errorlevel 1 exit /b %ERRORLEVEL%
"%~dp0RTLADSBTrackerService.exe" start
if errorlevel 1 exit /b %ERRORLEVEL%
echo.
echo RTL ADS-B Tracker service installed and started.
echo Browser URL: http://127.0.0.1:8090/
start "" "http://127.0.0.1:8090/"
CMD

cat > "${STAGE}/uninstall_service.cmd" <<'CMD'
@echo off
cd /d "%~dp0"
"%~dp0RTLADSBTrackerService.exe" stop
"%~dp0RTLADSBTrackerService.exe" uninstall
echo Service removed. ProgramData settings and logs were intentionally retained.
CMD

cat > "${STAGE}/restart_service.cmd" <<'CMD'
@echo off
cd /d "%~dp0"
"%~dp0RTLADSBTrackerService.exe" restart
CMD

cat > "${STAGE}/stop_service.cmd" <<'CMD'
@echo off
cd /d "%~dp0"
"%~dp0RTLADSBTrackerService.exe" stop
CMD

cat > "${STAGE}/status_service.cmd" <<'CMD'
@echo off
cd /d "%~dp0"
"%~dp0RTLADSBTrackerService.exe" status
pause
CMD

cat > "${STAGE}/open_tracker.cmd" <<'CMD'
@echo off
start "" "http://127.0.0.1:8090/"
CMD

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || printf unknown)"
cat > "${STAGE}/RELEASE_MANIFEST.txt" <<MANIFEST
RTL ADS-B Tracker Windows Service Release Candidate
Version: ${VERSION}
Source commit: ${GIT_COMMIT}
Built: $(date -Is 2>/dev/null || date)
Service host: WinSW ${WINSW_VERSION}
Backend bundle: PyInstaller onedir / native Windows Python
Runtime data location: %ProgramData%\RTL ADS-B Tracker\runtime
Application URL: http://127.0.0.1:8090/
MANIFEST

section "Create release ZIP"
rm -f "${ZIP_OUT}"
(
  cd "${BUILD}"
  zip -qr "${ZIP_OUT}" "${NAME}"
)

section "Release build complete"
printf 'Created: %s\n' "${ZIP_OUT}"
printf 'Install: unzip, then run install_service.cmd as Administrator.\n'
