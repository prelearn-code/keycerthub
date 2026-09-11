# Copyright (c) 2026 KeyCertHub Contributors
# SPDX-License-Identifier: Apache-2.0
cmake_minimum_required(VERSION 3.24)

project(keycerthub
    VERSION 0.0.1
    DESCRIPTION "Enterprise key and certificate management system"
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(CompilerWarnings)
include(Sanitizers)
include(Dependencies)

option(KEYCERTHUB_BUILD_TESTS    "Build unit and integration tests" ON)
option(KEYCERTHUB_BUILD_BENCH    "Build performance benchmarks"     OFF)
option(KEYCERTHUB_BUILD_FUZZ     "Build fuzz targets (Clang only)"  OFF)
option(KEYCERTHUB_ENABLE_ASAN    "Enable AddressSanitizer"          OFF)
option(KEYCERTHUB_ENABLE_UBSAN   "Enable UndefinedBehaviorSanitizer" OFF)
option(KEYCERTHUB_ENABLE_TSAN    "Enable ThreadSanitizer"           OFF)

# ---------------------------------------------------------------------------
# 核心库
# 注意：骨架阶段使用 GLOB 便于快速铺开；阶段 1 起改为显式文件列表，
#      避免新增文件未被重新配置的问题。
# ---------------------------------------------------------------------------
file(GLOB_RECURSE KEYCERTHUB_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")
list(REMOVE_ITEM KEYCERTHUB_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/main.cpp")

add_library(keycerthub_core STATIC ${KEYCERTHUB_SOURCES})
target_include_directories(keycerthub_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(keycerthub_core PUBLIC keycerthub::deps)
keycerthub_apply_warnings(keycerthub_core)
keycerthub_apply_sanitizers(keycerthub_core)

# ---------------------------------------------------------------------------
# 服务可执行文件
# ---------------------------------------------------------------------------
add_executable(keycerthub src/main.cpp)
target_link_libraries(keycerthub PRIVATE keycerthub_core)

# ---------------------------------------------------------------------------
# 测试与基准
# ---------------------------------------------------------------------------
if(KEYCERTHUB_BUILD_TESTS)
    enable_testing()
    file(GLOB_RECURSE KEYCERTHUB_TEST_SOURCES CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/*.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/*.cpp")
    if(KEYCERTHUB_TEST_SOURCES)
        add_executable(keycerthub_tests ${KEYCERTHUB_TEST_SOURCES})
        target_link_libraries(keycerthub_tests PRIVATE
            keycerthub_core GTest::gtest_main)
        keycerthub_apply_warnings(keycerthub_tests)
        include(GoogleTest)
        gtest_discover_tests(keycerthub_tests)
    else()
        message(STATUS "No test sources yet - skipping test target")
    endif()
endif()

if(KEYCERTHUB_BUILD_BENCH)
    find_package(benchmark CONFIG REQUIRED)
    file(GLOB_RECURSE KEYCERTHUB_BENCH_SOURCES CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/performance/*.cpp")
    if(KEYCERTHUB_BENCH_SOURCES)
        add_executable(keycerthub_bench ${KEYCERTHUB_BENCH_SOURCES})
        target_link_libraries(keycerthub_bench PRIVATE
            keycerthub_core benchmark::benchmark)
    endif()
endif()
