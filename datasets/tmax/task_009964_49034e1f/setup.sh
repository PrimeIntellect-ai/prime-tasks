#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential valgrind
    pip3 install pytest

    mkdir -p /home/user/file_manager/clib
    mkdir -p /home/user/file_manager/src

    cat << 'EOF' > /home/user/file_manager/clib/checksum.c
#include "checksum.h"
int compute_checksum(const char* filename) {
    int sum = 0;
    for(int i=0; filename[i] != '\0'; i++) {
        sum += filename[i];
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/file_manager/clib/checksum.h
int compute_checksum(const char* filename);
EOF

    cat << 'EOF' > /home/user/requests.csv
1000,fileA.txt,500,SIZE 100 >
1050,fileB.txt,100,SIZE 100 >
1250,fileC.txt,100,SIZE 200 - 0 >
1300,fileD.txt,300,SIZE 100 + 500 >
1450,fileE.txt,1000,SIZE 500 >
1500,fileF.txt,50,SIZE 10 >
1650,fileG.txt,2000,SIZE 1000 * 0 >
1850,fileH.txt,800,SIZE 100 >
EOF

    cat << 'EOF' > /home/user/file_manager/Cargo.toml
[package]
name = "file_manager"
version = "0.1.0"
edition = "2021"

# agent must add build = "build.rs" or leave as default which implies it
EOF

    cat << 'EOF' > /home/user/file_manager/build.rs
// agent needs to implement cc::Build or run gcc and emit cargo:rustc-link-search and cargo:rustc-link-lib
EOF

    cat << 'EOF' > /home/user/file_manager/src/main.rs
use std::ffi::CString;
use std::os::raw::c_char;

extern "C" {
    fn compute_checksum(filename: *const c_char) -> i32;
}

fn process_filename(name: &str) -> i32 {
    let c_str = CString::new(name).unwrap();
    let ptr = c_str.into_raw();
    // Intentionally leaking here:
    let result = unsafe { compute_checksum(ptr) };
    // Agent must add: unsafe { let _ = CString::from_raw(ptr); }
    result
}

// Agent must implement evaluate_rpn
fn evaluate_rpn(expr: &str, size: i32) -> i32 {
    0 // stub
}

fn main() {
    // Agent implements reading CSV, rate limiting, and outputting to log
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
