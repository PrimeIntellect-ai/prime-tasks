#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /app/vendored/log-chrono-0.1.5/src
    cat << 'EOF' > /app/vendored/log-chrono-0.1.5/Cargo.toml
[package]
name = "log-chrono"
version = "0.1.5"
edition = "2021"

[dependencies]

[build-dependencies]
cc = { path = "../missing-cc" }
EOF

    cat << 'EOF' > /app/vendored/log-chrono-0.1.5/src/lib.rs
pub fn parse_ts(ts: &str) -> Result<(), &'static str> {
    if ts.len() > 5 {
        Ok(())
    } else {
        Err("Invalid timestamp")
    }
}
EOF

    mkdir -p /app/corpora/evil /app/corpora/clean
    cat << 'EOF' > /app/corpora/evil/evil.jsonl
{"timestamp": "2023-10-10T10:00:00Z", "level": "INFO", "message": "User login OR 1=1"}
{"timestamp": "2023-10-10T10:01:00Z", "level": "ERROR", "message": "Failed query UNION SELECT * FROM users"}
{"timestamp": "2023-10-10T10:02:00Z", "level": "WARN", "message": "DROP TABLE logs;"}
{"timestamp": "2023-10-10T10:03:00Z", "level": "INFO", "message": "admin' --"}
EOF

    cat << 'EOF' > /app/corpora/clean/clean.jsonl
{"timestamp": "2023-10-10T10:00:00Z", "level": "INFO", "message": "User login successful"}
{"timestamp": "2023-10-10T10:01:00Z", "level": "ERROR", "message": "Failed to connect to DB"}
{"timestamp": "2023-10-10T10:02:00Z", "level": "WARN", "message": "Memory usage high"}
{"timestamp": "2023-10-10T10:03:00Z", "level": "INFO", "message": "Service started on port 8080"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
