#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/rust_lib/src

    cat << 'EOF' > /home/user/project/rust_lib/Cargo.toml
[package]
name = "rate_eval"
version = "0.1.0"
edition = "2021"

[lib]
name = "rate_eval"
crate-type = ["cdylib"]

[dependencies]
EOF

    cat << 'EOF' > /home/user/project/rust_lib/src/lib.rs
use std::os::raw::{c_char, c_int};

// TODO: Implement evaluate_rule extern "C" function here.
// TODO: Implement proptests.
EOF

    cat << 'EOF' > /home/user/project/runner.c
#include <stdio.h>

extern int evaluate_rule(const char* rule_str, int request_count);

int main() {
    int res1 = evaluate_rule("MAX:10", 5);
    int res2 = evaluate_rule("MAX:10", 15);
    int res3 = evaluate_rule("INVALID", 5);

    printf("Res1: %d\n", res1);
    printf("Res2: %d\n", res2);
    printf("Res3: %d\n", res3);

    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(RateRunner C)

add_executable(runner runner.c)

# Intentionally broken linkage path
target_link_directories(runner PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/wrong_dir)
target_link_libraries(runner PRIVATE rate_eval)
EOF

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
