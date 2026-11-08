#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make rustc cargo espeak-ng
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil
    espeak-ng -w /app/sys_audio.wav "The missing edges are core to network, network to database, and database to render."

    python3 -c '
import os
for i in range(100):
    with open(f"/app/corpus/clean/file_{i}.txt", "w") as f:
        f.write("A->B\nB->C\nC->D\n")
for i in range(50):
    with open(f"/app/corpus/evil/cycle_{i}.txt", "w") as f:
        f.write("A->B\nB->C\nC->A\n")
for i in range(50):
    with open(f"/app/corpus/evil/encoding_{i}.txt", "wb") as f:
        f.write(b"A->B\nB->C\n" + b"\xff\xfe\n")
    '

    mkdir -p /home/user/system_builder/rust_backend/src

    cat << 'EOF' > /home/user/system_builder/rust_backend/Cargo.toml
[package]
name = "rust_backend"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/system_builder/rust_backend/src/lib.rs
use std::ffi::CStr;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn validate_encoding(input: *const c_char) -> *const c_char {
    let c_str = unsafe { CStr::from_ptr(input) };
    let s = c_str.to_string_lossy().into_owned();
    s.as_ptr() as *const c_char
}
EOF

    cat << 'EOF' > /home/user/system_builder/Makefile
all: dep_resolver

dep_resolver: main.o
	gcc -o dep_resolver -lrust_backend main.o -L./rust_backend/target/debug

main.o: main.c
	gcc -c main.c
EOF

    cat << 'EOF' > /home/user/system_builder/main.c
#include <stdio.h>

int validate_file(const char* filepath) {
    return 0;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    return validate_file(argv[1]);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
