#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake build-essential cargo rustc
    pip3 install pytest

    mkdir -p /home/user/project/c_src
    mkdir -p /home/user/project/rust_src/src

    cat << 'EOF' > /home/user/project/c_src/validator.c
#define _POSIX_C_SOURCE 199309L
#include <time.h>
#include <stddef.h>

// BUG: Hidden visibility prevents the symbol from being exported in the shared library
__attribute__((visibility("hidden")))
int validate_request(int client_id) {
    struct timespec ts;
    ts.tv_sec = 0;
    ts.tv_nsec = 500000; // 0.5 ms
    nanosleep(&ts, NULL);
    return (client_id > 0) ? 1 : 0;
}
EOF

    cat << 'EOF' > /home/user/project/c_src/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(Validator C)
add_library(validator SHARED validator.c)
EOF

    cat << 'EOF' > /home/user/project/rust_src/Cargo.toml
[package]
name = "rust_api"
version = "0.1.0"
edition = "2021"
build = "build.rs"

[dependencies]
EOF

    cat << 'EOF' > /home/user/project/rust_src/build.rs
fn main() {
    println!("cargo:rustc-link-search=native=/home/user/project/c_src/build");
    println!("cargo:rustc-link-lib=dylib=validator");
    println!("cargo:rustc-link-arg=-Wl,-rpath,/home/user/project/c_src/build");
}
EOF

    cat << 'EOF' > /home/user/project/rust_src/src/main.rs
use std::env;
use std::time::Instant;

extern "C" {
    fn validate_request(client_id: i32) -> i32;
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        std::process::exit(1);
    }
    let client_id: i32 = args[1].parse().unwrap_or(0);

    let start = Instant::now();
    let res = unsafe { validate_request(client_id) };
    let duration = start.elapsed();

    println!("Result: {}, Time: {} us", res, duration.as_micros());
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
