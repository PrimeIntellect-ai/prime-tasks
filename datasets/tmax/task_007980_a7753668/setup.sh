#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        cmake \
        make \
        g++ \
        sqlite3 \
        libsqlite3-dev \
        cargo \
        rustc

    pip3 install pytest

    mkdir -p /home/user/project/src /home/user/project/rust_lib/src /home/user/project/schema

    cat << 'EOF' > /home/user/project/schema/migrate.sql
ALTER TABLE config ADD COLUMN version INTEGER DEFAULT 2;
EOF

    sqlite3 /home/user/project/db.sqlite "CREATE TABLE config (id INTEGER PRIMARY KEY, name TEXT); INSERT INTO config (name) VALUES ('SystemDB');"

    cat << 'EOF' > /home/user/project/rust_lib/Cargo.toml
[package]
name = "rust_lib"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib"]
EOF

    cat << 'EOF' > /home/user/project/rust_lib/src/lib.rs
use std::ffi::CString;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn get_system_name() -> *const c_char {
    let s = CString::new("PolyglotGraphSystem").unwrap();
    s.as_ptr() // Bug: returns pointer to dropped value.
}

#[no_mangle]
pub extern "C" fn free_system_name(s: *mut c_char) {
    unsafe {
        if s.is_null() { return; }
        let _ = CString::from_raw(s);
    }
}
EOF

    cat << 'EOF' > /home/user/project/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(polyglot)

set(CMAKE_CXX_STANDARD 17)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/rust_lib/target/debug/librust_lib.a
    COMMAND cargo build
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/rust_lib
)
add_custom_target(rust_target DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/rust_lib/target/debug/librust_lib.a)

add_executable(myapp src/main.cpp src/wrapper.cpp)
add_dependencies(myapp rust_target)
target_link_libraries(myapp sqlite3)
# Bug: Missing linking to the rust library and dl/pthread/m.
EOF

    cat << 'EOF' > /home/user/project/src/wrapper.h
#pragma once
extern "C" {
    const char* get_system_name();
    void free_system_name(char* s);
}
EOF

    cat << 'EOF' > /home/user/project/src/wrapper.cpp
#include "wrapper.h"
// Wrapper implementations or additional logic could go here.
EOF

    cat << 'EOF' > /home/user/project/src/main.cpp
#include <iostream>
#include <fstream>
#include <sqlite3.h>
#include "wrapper.h"

int main() {
    sqlite3* db;
    if (sqlite3_open("../db.sqlite", &db) != SQLITE_OK) {
        return 1;
    }

    sqlite3_stmt* stmt;
    const char* query = "SELECT version FROM config LIMIT 1;";
    if (sqlite3_prepare_v2(db, query, -1, &stmt, nullptr) != SQLITE_OK) {
        // Migration not applied!
        return 2;
    }

    int version = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        version = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    if (version != 2) return 3;

    const char* sys_name = get_system_name();

    std::ofstream out("../output.log");
    out << "System OK. Name: " << sys_name << ", Version: " << version << std::endl;
    out.close();

    free_system_name(const_cast<char*>(sys_name));
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
