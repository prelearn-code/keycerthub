# 第三方依赖。见总体设计文档第四章。
find_package(OpenSSL REQUIRED)
find_package(nlohmann_json CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)
find_package(yaml-cpp CONFIG REQUIRED)
find_package(SQLite3 REQUIRED)
find_package(PostgreSQL REQUIRED)

if(KEYCERTHUB_BUILD_TESTS)
    find_package(GTest CONFIG REQUIRED)
endif()

add_library(keycerthub_deps INTERFACE)
add_library(keycerthub::deps ALIAS keycerthub_deps)
target_link_libraries(keycerthub_deps INTERFACE
    OpenSSL::SSL
    OpenSSL::Crypto
    nlohmann_json::nlohmann_json
    spdlog::spdlog
    yaml-cpp::yaml-cpp
    SQLite::SQLite3
    PostgreSQL::PostgreSQL)
target_compile_definitions(keycerthub_deps INTERFACE
    KEYCERTHUB_VERSION="${PROJECT_VERSION}")
