#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/telemetry_parser/src

    cat << 'EOF' > /home/user/data/service_a.log
{"timestamp": "2023-10-25T14:31:00Z", "service": "A", "msg": "Booting up"}
{"timestamp": "2023-10-25T14:35:00Z", "service": "A", "msg": "Processing"}
EOF

    cat << 'EOF' > /home/user/data/service_b.log
{"timestamp": "2023-10-25T14:30:30Z", "service": "B", "msg": "Init"}
{"timestamp": "2023-10-25T14:32:00Z", "service": "B", "msg": "Missing bracket"
{"timestamp": "2023-10-25T14:34:00Z", "service": "B", "msg": "Normal"}
{corrupted nonsense line}
EOF

    cat << 'EOF' > /home/user/data/service_c.log
{"timestamp": "2023-10-25T14:30:00Z+00:00", "service": "C", "msg": "Bad timezone start"}
{"timestamp": "2023-10-25T14:33:00Z", "service": "C", "msg": "Normal message"}
EOF

    cat << 'EOF' > /home/user/telemetry_parser/Cargo.toml
[package]
name = "telemetry_parser"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
chrono = "0.4"
EOF

    cat << 'EOF' > /home/user/telemetry_parser/src/main.rs
use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

#[derive(Debug, Deserialize, Serialize, Clone)]
struct LogEntry {
    timestamp: String,
    service: String,
    msg: String,
}

fn main() {
    let files = vec![
        "/home/user/data/service_a.log",
        "/home/user/data/service_b.log",
        "/home/user/data/service_c.log",
    ];

    let mut all_logs = Vec::new();

    for file_path in files {
        let file = File::open(file_path).unwrap();
        let reader = BufReader::new(file);

        for line in reader.lines() {
            let line = line.unwrap();
            // Bug 2: Panics on corrupted input
            let entry: LogEntry = serde_json::from_str(&line).unwrap();

            // Bug 1: Panics on bad timezone format from Service C
            let _dt = chrono::DateTime::parse_from_rfc3339(&entry.timestamp).unwrap();

            all_logs.push(entry);
        }
    }

    // Bug 3: No sorting done here

    let output_file = File::create("/home/user/timeline_output.json").unwrap();
    serde_json::to_writer_pretty(output_file, &all_logs).unwrap();
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
