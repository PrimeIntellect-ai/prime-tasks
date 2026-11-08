#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make cargo rustc jq
    pip3 install pytest

    mkdir -p /home/user/rust_linter/src
    mkdir -p /home/user/rust_linter/c_src
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/corpora/eval_clean
    mkdir -p /home/user/corpora/eval_evil
    mkdir -p /app

    # Create dummy legacy validator
    cat << 'EOF' > /app/legacy_validator.c
#include <stdio.h>
int main() { return 0; }
EOF
    gcc -o /app/legacy_validator /app/legacy_validator.c
    strip /app/legacy_validator
    rm /app/legacy_validator.c

    # Create Rust project
    cat << 'EOF' > /home/user/rust_linter/Cargo.toml
[package]
name = "rust_linter"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/rust_linter/build.rs
fn main() {
    println!("cargo:rustc-link-search=native=c_src");
    println!("cargo:rustc-link-lib=static=vm");
}
EOF

    cat << 'EOF' > /home/user/rust_linter/src/main.rs
mod parser;

extern "C" {
    fn evaluate_bytecode(script: *const u8, len: usize) -> i32;
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        std::process::exit(1);
    }
    let content = std::fs::read_to_string(&args[1]).unwrap();
    let script = parser::parse_manifest(&content);

    let is_evil = unsafe { evaluate_bytecode(script.as_ptr(), script.len()) };
    if is_evil != 0 {
        std::process::exit(1);
    }
}
EOF

    cat << 'EOF' > /home/user/rust_linter/src/parser.rs
use serde::Deserialize;

#[derive(Deserialize)]
struct Manifest {
    script: String,
}

pub fn parse_manifest(content: &str) -> &str {
    let manifest: Manifest = serde_json::from_str(content).unwrap();
    &manifest.script
}
EOF

    # Create C source and broken Makefile
    cat << 'EOF' > /home/user/rust_linter/c_src/vm.c
#include <stdint.h>
#include <stddef.h>

int evaluate_bytecode(const uint8_t* script, size_t len) {
    return 0;
}
EOF

    cat << 'EOF' > /home/user/rust_linter/c_src/Makefile
libvm.a: vm.o
    ar rcs libvm.a vm.o

vm.o: vm.c
gcc -c vm.c -o vm.o
EOF

    # Generate corpora
    echo '{"script": "0100"}' > /home/user/corpora/clean/1.json
    echo '{"script": "010B03"}' > /home/user/corpora/evil/1.json
    echo '{"script": "0105"}' > /home/user/corpora/eval_clean/1.json
    echo '{"script": "010C03"}' > /home/user/corpora/eval_evil/1.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
