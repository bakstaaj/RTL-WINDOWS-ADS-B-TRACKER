#!/usr/bin/env bash
# Build the reproducible Linux-container Windows-x64 cross-toolchain image.
# Intended shell: MSYS2 UCRT64. This script does not invoke Windows shells.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME='rtl-windows-adsb-builder:dev'

[[ "${MSYSTEM:-}" == "UCRT64" ]] || {
    printf 'ERROR: Run from MSYS2 UCRT64.\n' >&2
    exit 1
}

command -v docker >/dev/null 2>&1 || {
    printf 'ERROR: docker is not available in PATH.\n' >&2
    exit 1
}

cd "${PROJECT_ROOT}"
printf 'Building Docker image %s from %s\n' "${IMAGE_NAME}" "${PROJECT_ROOT}"
docker build -f docker/Dockerfile.windows-x64 -t "${IMAGE_NAME}" .
printf 'Docker image build complete: %s\n' "${IMAGE_NAME}"
