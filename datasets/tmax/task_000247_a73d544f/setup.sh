#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc make
    pip3 install pytest

    mkdir -p /app/vendored/telemetry-processor/src
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /app/vendored/telemetry-processor/Cargo.toml
[package]
name = "telemetry-processor"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", feature = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /app/vendored/telemetry-processor/Makefile
build:
	RUSTFLAGS="-C target-cpu=xyz123" cargo build --release
EOF

    cat << 'EOF' > /app/vendored/telemetry-processor/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    cat << 'EOF' > /app/corpora/clean/clean.jsonl
{"sensor_id": "A", "value": 50.0, "message": "ok"}
{"sensor_id": "A", "value": 60.0, "message": "ok2"}
EOF

    cat << 'EOF' > /app/corpora/evil/evil.jsonl
{"sensor_id": "A", "value": 50.0, "message": "bad \uDEAD string"}
{"sensor_id": "A", "value": 9000.0, "message": "out of bounds"}
{"sensor_id": "A", "value": 50.0, "message": "ok"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
