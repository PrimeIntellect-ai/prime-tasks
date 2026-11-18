#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl build-essential gcc-aarch64-linux-gnu libc6-dev-arm64-cross
pip3 install pytest

# Install Rust globally
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export PATH=/usr/local/cargo/bin:$PATH
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
rustup target add aarch64-unknown-linux-gnu
chmod -R 777 /usr/local/rustup /usr/local/cargo

useradd -m -s /bin/bash user || true

export HOME=/home/user
mkdir -p $HOME/mobile_telemetry/src

cat << 'EOF' > $HOME/mobile_telemetry/Cargo.toml
[package]
name = "mobile_telemetry"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
libc = "0.2"

[build-dependencies]
cc = "1.0"
EOF

cat << 'EOF' > $HOME/mobile_telemetry/build.rs
fn main() {
    cc::Build::new()
        .file("src/legacy_decoder.c")
        .compile("legacy_decoder");
    println!("cargo:rerun-if-changed=src/legacy_decoder.c");
}
EOF

cat << 'EOF' > $HOME/mobile_telemetry/src/legacy_decoder.c
#include <stdint.h>
#include <stddef.h>

// Buggy function: skips 3 bytes on 0xFF but doesn't check bounds
size_t decode_stream(const uint8_t* input, size_t in_len, uint8_t* output) {
    size_t in_idx = 0;
    size_t out_idx = 0;
    while (in_idx < in_len) {
        if (input[in_idx] == 0xFF) {
            in_idx += 3; // BUG: Out of bounds read possible here
            continue;
        }
        output[out_idx++] = input[in_idx++];
    }
    return out_idx;
}
EOF

cat << 'EOF' > $HOME/mobile_telemetry/src/main.rs
use std::fs;
use std::io::Write;
use serde::Serialize;

extern "C" {
    fn decode_stream(input: *const u8, in_len: usize, output: *mut u8) -> usize;
}

#[derive(Serialize)]
#[serde(tag = "type", content = "value")]
#[serde(rename_all = "camelCase")]
enum Metric {
    #[serde(rename = "battery")]
    Battery(u32),
    #[serde(rename = "device")]
    Device(String),
}

// TODO: Implement get_pipeline_arch() -> &'static str

fn main() {
    let raw = fs::read("/home/user/telemetry.bin").unwrap();
    let mut decoded = vec![0u8; raw.len()];

    let decoded_len = unsafe {
        decode_stream(raw.as_ptr(), raw.len(), decoded.as_mut_ptr())
    };
    decoded.truncate(decoded_len);

    // TODO: Implement parse_telemetry state machine here and write to /home/user/parsed_metrics.json
}
EOF

cat << 'EOF' > $HOME/create_bin.py
import struct
with open("/home/user/telemetry.bin", "wb") as f:
    # Packet 1
    f.write(bytes([0xAA, 1, 4, 0, 0, 0, 42, 47]))
    # Skip marker
    f.write(bytes([0xFF, 0x00, 0x00]))
    # Packet 2
    f.write(bytes([0xAA, 2, 5, 80, 73, 88, 69, 76, 113]))
    # Bug trigger
    f.write(bytes([0xFF, 0x12]))
EOF
python3 $HOME/create_bin.py

cat << 'EOF' >> $HOME/.bashrc
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export PATH=/usr/local/cargo/bin:$PATH
EOF

chown -R user:user $HOME
chmod -R 777 $HOME
