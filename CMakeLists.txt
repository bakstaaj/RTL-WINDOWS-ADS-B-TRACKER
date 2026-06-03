cmake_minimum_required(VERSION 3.22)

project(RTLWindowsADSBTracker
    VERSION 0.1.0
    LANGUAGES C
)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(RTLSDR REQUIRED IMPORTED_TARGET librtlsdr)

add_executable(rtl_dual_device_probe
    src/native/rtl_dual_device_probe.c
)

target_link_libraries(rtl_dual_device_probe PRIVATE PkgConfig::RTLSDR)

if(MINGW)
    target_compile_options(rtl_dual_device_probe PRIVATE -Wall -Wextra -Wpedantic)
endif()
