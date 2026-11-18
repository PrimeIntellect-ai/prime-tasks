#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/project/src

    cat << 'EOF' > /home/user/project/Cargo.toml
[package]
name = "recovery_app"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/project/build.rs
use std::env;
use std::fs;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=fuzz_crash.bin");

    if let Ok(val) = env::var("RECOVERED_KEY") {
        println!("cargo:rustc-env=APP_KEY={}", val);
        return;
    }

    let data = fs::read("fuzz_crash.bin").expect("Failed to read crash dump");

    // Panics here due to invalid UTF-8 in the raw memory dump
    let content = String::from_utf8(data).expect("Crash dump contains invalid UTF-8");

    for line in content.lines() {
        if let Some(key) = line.strip_prefix("APP_SECRET_KEY=") {
            println!("cargo:rustc-env=APP_KEY={}", key);
            return;
        }
    }
    panic!("Key not found in crash dump");
}
EOF

    cat << 'EOF' > /home/user/project/src/main.rs
fn main() {
    let key = env!("APP_KEY");
    println!("Recovered key: {}", key);
}
EOF

    head -c 500 /dev/urandom > /home/user/project/fuzz_crash.bin
    echo -n "APP_SECRET_KEY=9a3f2b1e8c7d6a5b4c3d2e1f0a9b8c7d" >> /home/user/project/fuzz_crash.bin
    head -c 500 /dev/urandom >> /home/user/project/fuzz_crash.bin
    printf "\xff\xfe\xff" >> /home/user/project/fuzz_crash.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
