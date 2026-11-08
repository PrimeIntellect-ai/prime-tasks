#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl espeak-ng cargo
    pip3 install pytest

    # Create directories
    mkdir -p /app/audio /app/db /app/pii-filter/src /app/corpus/clean /app/corpus/evil

    # Generate audio
    espeak-ng -w /app/audio/distress_signal.wav "Evacuation order authorized for sector seven"

    # Generate DB files
    cat << 'EOF' > /app/db/sys_service.log
[2023-10-27T08:10:00Z] INFO: Service started
[2023-10-27T08:12:00Z] WARN: High latency
[2023-10-27T08:14:02Z] FATAL: Storage node unresponsive. Initiating dump.
EOF

    cat << 'EOF' > /app/db/telemetry.wal
TX_ID: 9400
TX_ID: 9401
TX_ID: 9402
EOF

    # Generate Rust project
    cat << 'EOF' > /app/pii-filter/Cargo.toml
[package]
name = "pii-filter"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/pii-filter/src/main.rs
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        std::process::exit(0);
    }
    let _content = fs::read_to_string(&args[1]).unwrap();
    // TODO: implement filtering
    std::process::exit(0);
}
EOF

    # Generate corpus
    python3 -c '
import os

for i in range(50):
    with open(f"/app/corpus/clean/file_{i}.txt", "w") as f:
        f.write("Clean log entry\n")

for i in range(20):
    with open(f"/app/corpus/evil/ssn_{i}.txt", "w") as f:
        f.write("User SSN is 123-45-6789\n")
for i in range(15):
    with open(f"/app/corpus/evil/aws_{i}.txt", "w") as f:
        f.write("Key: AKIAIOSFODNN7EXAMPLE\n")
for i in range(15):
    with open(f"/app/corpus/evil/fmt_{i}.txt", "w") as f:
        f.write("Payload: %08x.%08x.%08x\n")
'

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
