#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential golang rustc cargo espeak
    pip3 install pytest

    mkdir -p /app/audio
    mkdir -p /app/src/rust_engine/src
    mkdir -p /app/src/waf_filter
    mkdir -p /app/bin
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate audio
    espeak -w /app/audio/security_policy.wav "For the new deployment, the maximum allowed nesting depth is seven."

    # Rust Engine
    cat << 'EOF' > /app/src/rust_engine/src/lib.rs
#[no_mangle]
pub extern "C" fn evaluate_safe() -> i32 {
    0
}

// Buggy function to test borrow checker
pub fn get_status<'a>() -> &'a str {
    let s = String::from("active");
    s.as_str() // Error: returns a reference to data owned by the current function
}
EOF

    cat << 'EOF' > /app/src/rust_engine/Cargo.toml
[package]
name = "rust_engine"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib"]
EOF

    # Corpora
    echo -n "(1 + 2) * 3" > /app/corpus/clean/test1.txt
    echo -n "(((((1)))))" > /app/corpus/clean/test2.txt
    echo -n "(((((((1)))))))" > /app/corpus/clean/test3.txt

    echo -n "((((((((1))))))))" > /app/corpus/evil/test1.txt
    echo -n "1 + 2; DROP TABLE users;" > /app/corpus/evil/test2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
