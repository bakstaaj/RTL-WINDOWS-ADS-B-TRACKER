#!/usr/bin/env bash
# Build the native MSYS2 UCRT64 RTL-SDR device probe.
# This native build is used for live Windows USB/RTL testing.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/native-ucrt64"
DIST_DIR="${PROJECT_ROOT}/dist/native-windows"

[[ "${MSYSTEM:-}" == "UCRT64" ]] || {
    printf 'ERROR: Run from MSYS2 UCRT64.\n' >&2
    exit 1
}

pkg-config --exists librtlsdr || {
    printf 'ERROR: librtlsdr development package is not available through pkg-config.\n' >&2
    exit 1
}

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

cmake -S "${PROJECT_ROOT}" -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build "${BUILD_DIR}"

cp -f "${BUILD_DIR}/rtl_dual_device_probe.exe" "${DIST_DIR}/rtl_dual_device_probe.exe"

printf '\nNative Windows probe built:\n  %s/rtl_dual_device_probe.exe\n' "${DIST_DIR}"
