#!/usr/bin/env bash
# Compile a minimal Windows x64 executable inside the Docker build environment.
# Intended shell: MSYS2 UCRT64. This script does not invoke Windows shells.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT_WIN="$(cygpath -w "${PROJECT_ROOT}")"
IMAGE_NAME='rtl-windows-adsb-builder:dev'

[[ "${MSYSTEM:-}" == "UCRT64" ]] || {
    printf 'ERROR: Run from MSYS2 UCRT64.\n' >&2
    exit 1
}

mkdir -p "${PROJECT_ROOT}/dist/windows-x64"

cat > "${PROJECT_ROOT}/test_output/windows_x64_toolchain_probe.c" <<'C_EOF'
#include <stdio.h>

int main(void)
{
    puts("RTL-Windows-ADS-B-Tracker Windows x64 cross-toolchain probe");
    return 0;
}
C_EOF

printf 'Compiling a Windows x64 executable inside Docker...\n'
MSYS_NO_PATHCONV=1 docker run --rm \
    --mount "type=bind,source=${PROJECT_ROOT_WIN},target=/work" \
    -w /work \
    "${IMAGE_NAME}" \
    bash -lc 'x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -o dist/windows-x64/toolchain_probe.exe test_output/windows_x64_toolchain_probe.c && file dist/windows-x64/toolchain_probe.exe'

printf '\nCreated: %s/dist/windows-x64/toolchain_probe.exe\n' "${PROJECT_ROOT}"
printf 'This is a build-environment test artifact; it is excluded from Git.\n'
