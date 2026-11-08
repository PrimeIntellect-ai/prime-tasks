#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo rustc
    pip3 install pytest

    mkdir -p /home/user/rust_waf/src
    cat << 'EOF' > /home/user/rust_waf/Cargo.toml
[package]
name = "rust_waf"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/rust_waf/src/lib.rs
pub mod parser;
pub mod rules;

use std::os::raw::c_char;
use std::ffi::CStr;

#[no_mangle]
pub extern "C" fn compute_hazard(payload: *const c_char) -> u32 {
    let c_str = unsafe {
        if payload.is_null() {
            return 0;
        }
        CStr::from_ptr(payload)
    };
    let s = c_str.to_string_lossy();
    let mut score = 0;
    if s.contains("SELECT") { score += 500; }
    if s.contains("UNION") { score += 500; }
    if s.contains("<script>") { score += 500; }
    if s.contains("DROP") { score += 500; }
    score
}
EOF

    cat << 'EOF' > /home/user/rust_waf/src/parser.rs
use crate::rules::*;
pub fn parse() {}
EOF

    cat << 'EOF' > /home/user/rust_waf/src/rules.rs
use crate::parser::*;
pub fn rule() {}
EOF

    mkdir -p /app/corpus/evil /app/corpus/clean
    cat << 'EOF' > /app/legacy_scorer.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 0;
    char *payload = argv[1];
    int score = 0;
    if (strstr(payload, "SELECT")) score += 500;
    if (strstr(payload, "UNION")) score += 500;
    if (strstr(payload, "<script>")) score += 500;
    if (strstr(payload, "DROP")) score += 500;

    printf("Score: %d\n", score);
    if (score > 1337) return 1;
    return 0;
}
EOF
    gcc -O2 /app/legacy_scorer.c -o /app/legacy_scorer
    strip /app/legacy_scorer
    rm /app/legacy_scorer.c

    for i in $(seq 1 50); do
        echo "SELECT UNION DROP payload $i" > /app/corpus/evil/file_$i.txt
        echo "Normal request data $i" > /app/corpus/clean/file_$i.txt
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
