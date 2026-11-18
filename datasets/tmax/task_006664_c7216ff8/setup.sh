#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake
    pip3 install pytest

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/test
    mkdir -p /home/user/project/include

    cat << 'EOF' > /home/user/project/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(SchemaMigrator)

set(CMAKE_CXX_STANDARD 17)

include_directories(include)

# Shared library
add_library(encoder SHARED src/encoder.cpp)

# Test executable
add_executable(migrator_test src/migrator.cpp test/test_migrator.cpp)

# BUG: Missing target_link_libraries and RPATH configuration
# target_link_libraries(migrator_test PRIVATE encoder)
# set_target_properties(migrator_test PROPERTIES INSTALL_RPATH "$ORIGIN")
EOF

    cat << 'EOF' > /home/user/project/include/encoder.h
#ifndef ENCODER_H
#define ENCODER_H
#include <cstdint>
#include <cstddef>

// Converts UTF-16 LE to UTF-8 (Simplified stub for testing)
void utf16_le_to_utf8(const uint16_t* utf16_str, size_t utf16_len, char* utf8_out);

#endif
EOF

    cat << 'EOF' > /home/user/project/src/encoder.cpp
#include "encoder.h"

void utf16_le_to_utf8(const uint16_t* utf16_str, size_t utf16_len, char* utf8_out) {
    // Simplified conversion assuming ASCII characters in UTF-16
    for (size_t i = 0; i < utf16_len; ++i) {
        utf8_out[i] = static_cast<char>(utf16_str[i] & 0xFF);
    }
}
EOF

    cat << 'EOF' > /home/user/project/include/migrator.h
#ifndef MIGRATOR_H
#define MIGRATOR_H
#include <string>
#include <cstdint>

struct LegacyRecord {
    uint32_t id;
    uint16_t name_len;
    const uint16_t* name_utf16_le;
};

std::string migrate_record(const LegacyRecord& record);

#endif
EOF

    cat << 'EOF' > /home/user/project/src/migrator.cpp
#include "migrator.h"
#include "encoder.h"
#include <cstring>

std::string migrate_record(const LegacyRecord& record) {
    // BUG: Missing space for null terminator
    char* utf8_name = new char[record.name_len]; 

    utf16_le_to_utf8(record.name_utf16_le, record.name_len, utf8_name);

    // BUG: writing out of bounds
    utf8_name[record.name_len] = '\0'; 

    std::string result = "{\"id\":" + std::to_string(record.id) + ",\"name\":\"" + std::string(utf8_name) + "\"}";

    delete[] utf8_name;
    return result;
}
EOF

    cat << 'EOF' > /home/user/project/test/test_migrator.cpp
#include "migrator.h"
#include <iostream>
#include <cassert>
#include <vector>

std::vector<uint16_t> setup_mock_data() {
    std::vector<uint16_t> mock_utf16;
    // TASK: Fill mock_utf16 with UTF-16 LE bytes for "Test"
    // e.g. mock_utf16.push_back('T'); ...
    return mock_utf16;
}

int main() {
    std::vector<uint16_t> name_data = setup_mock_data();
    if (name_data.empty()) {
        std::cerr << "Mock data not set up!" << std::endl;
        return 1;
    }

    LegacyRecord rec;
    rec.id = 42;
    rec.name_len = name_data.size();
    rec.name_utf16_le = name_data.data();

    std::string json = migrate_record(rec);
    std::cout << "Migrated: " << json << std::endl;

    assert(json == "{\"id\":42,\"name\":\"Test\"}");

    std::cout << "All tests passed." << std::endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
