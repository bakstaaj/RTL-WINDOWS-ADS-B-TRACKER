#!/usr/bin/env bash
# Build pinned Windows-native Dump1090 into ignored output.
# Intended environment: MSYS2 UCRT64.
#
# The dependency checkout is bounded and fetches only the tested upstream commit.
# No generated executable or third-party runtime data is committed by this tool.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="${PROJECT_ROOT}/external/dump1090/UPSTREAM_COMMIT.txt"
PATCH_FILE="${PROJECT_ROOT}/external/dump1090/patches/0001-fix-http-json-size-parameter-calls.patch"
BUILD_ROOT="${PROJECT_ROOT}/build/third_party/dump1090"
SOURCE_DIR="${BUILD_ROOT}/Dump1090-src"
SRC_DIR="${SOURCE_DIR}/src"
DIST_DIR="${PROJECT_ROOT}/dist/third_party/dump1090"
UPSTREAM_URL='https://github.com/gvanem/Dump1090.git'
FETCH_TIMEOUT_SECONDS=120
BUILD_TIMEOUT_SECONDS=900

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

[[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Run from MSYS2 UCRT64."
[[ -s "${PIN_FILE}" ]] || fail "Missing upstream commit pin: ${PIN_FILE}"
[[ -s "${PATCH_FILE}" ]] || fail "Missing compatibility patch: ${PATCH_FILE}"

for command_name in git python3 make gcc windres cygpath timeout; do
    command -v "${command_name}" >/dev/null 2>&1 || fail "${command_name} is missing."
done

PINNED_COMMIT="$(tr -d '[:space:]' < "${PIN_FILE}")"
[[ "${PINNED_COMMIT}" =~ ^[0-9a-f]{40}$ ]] ||
    fail "Pinned upstream commit is not a complete commit hash."

printf 'Building Dump1090 pinned commit: %s\n' "${PINNED_COMMIT}"
printf 'Fetching only the pinned commit from: %s\n' "${UPSTREAM_URL}"

# Build and distribution directories are excluded from Git.
rm -rf "${BUILD_ROOT}"
mkdir -p "${SOURCE_DIR}" "${DIST_DIR}"
git -C "${SOURCE_DIR}" init -q
git -C "${SOURCE_DIR}" remote add origin "${UPSTREAM_URL}"

timeout -k 5s "${FETCH_TIMEOUT_SECONDS}s" env GIT_TERMINAL_PROMPT=0 \
    git -C "${SOURCE_DIR}" fetch --no-tags --depth 1 origin "${PINNED_COMMIT}" ||
    fail "Timed out or failed fetching the pinned Dump1090 commit."
git -C "${SOURCE_DIR}" checkout --detach -q FETCH_HEAD

FETCHED_COMMIT="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
[[ "${FETCHED_COMMIT}" == "${PINNED_COMMIT}" ]] ||
    fail "Fetched commit does not match the pinned tested commit."
printf 'Fetched pinned commit: %s\n' "${FETCHED_COMMIT}"

git -C "${SOURCE_DIR}" apply --check "${PATCH_FILE}" ||
    fail "Tracked Dump1090 compatibility patch no longer applies to the pinned commit."
git -C "${SOURCE_DIR}" apply "${PATCH_FILE}"
printf 'Applied tracked compatibility patch: %s\n' "${PATCH_FILE}"

GEN_RESULTS_WIN="$(
python3 - <<'PY'
import os
temp = os.environ.get("TEMP", "C:/msys64/tmp").replace("\\", "/")
print(temp + "/dump1090/standing-data/results")
PY
)"
GEN_RESULTS="$(cygpath -u "${GEN_RESULTS_WIN}")"

# Upstream supports --mingw for generated-data verification; use that path
# under the native MSYS2 GCC workflow. The Makefile Python command is also
# overridden from the Windows Launcher form to the available MSYS2 command.
timeout -k 15s "${BUILD_TIMEOUT_SECONDS}s" bash -lc "
    set -euo pipefail
    cd \"${SRC_DIR}\"
    mkdir -p objects
    python3 ../tools/gen_data.py --clean
    python3 ../tools/gen_data.py --mingw --gen-c objects/gen-code-blocks.c
    cp -f \"${GEN_RESULTS}/gen_data.h\" objects/gen_data.h
    make -f Makefile.MinGW CPU=x64 PYTHON=python3 -j4
" || fail "Dump1090 generation/build failed or exceeded the bounded build interval."

[[ -x "${SOURCE_DIR}/dump1090.exe" ]] ||
    fail "Build completed without expected dump1090.exe output."
[[ -s "${SOURCE_DIR}/airport-codes.csv" ]] ||
    fail "Required Dump1090 runtime airport database is missing from the pinned checkout."

rm -rf "${DIST_DIR:?}/"*
cp -f "${SOURCE_DIR}/dump1090.exe" "${DIST_DIR}/dump1090.exe"
cp -f "${SOURCE_DIR}/airport-codes.csv" "${DIST_DIR}/airport-codes.csv"

if [[ -f "${SOURCE_DIR}/LICENSE" ]]; then
    cp -f "${SOURCE_DIR}/LICENSE" "${DIST_DIR}/LICENSE.Dump1090.txt"
fi

printf '\nBuilt Windows ADS-B decoder runtime output:\n'
printf '  %s/dump1090.exe\n' "${DIST_DIR}"
printf '  %s/airport-codes.csv\n' "${DIST_DIR}"
printf 'Generated runtime output remains ignored by Git.\n'
