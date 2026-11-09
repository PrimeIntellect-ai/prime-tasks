#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/log_processor/src

    # Create the binary disk image with embedded logs
    python3 -c '
import random
import json
import struct

random.seed(42)
with open("/home/user/disk_image.bin", "wb") as f:
    for i in range(100):
        # Write random binary garbage
        f.write(bytes([random.randint(0, 255) for _ in range(128)]))

        # Write the log entry
        # Sensor values that will demonstrate f32 precision loss when summed
        val = 100000.0 + (i * 0.125) 
        log = {"timestamp": 1670000000 + i, "sensor_val": val}
        log_str = f"LOG_ENTRY: {json.dumps(log)}\n"
        f.write(log_str.encode("ascii"))

    # Write some trailing garbage
    f.write(bytes([random.randint(0, 255) for _ in range(512)]))
'

    # Create the Rust project
    cat << 'EOF' > /home/user/log_processor/Cargo.toml
[package]
name = "log_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/log_processor/src/main.rs
use std::env;
use std::fs::File;
use std::io::{self, BufRead, Write};
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Debug)]
struct LogEntry {
    timestamp: u64,
    sensor_val: f64,
}

#[derive(Serialize)]
struct Metrics {
    processed_count: usize,
    total_sensor_value: f64,
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        eprintln!("Usage: log_processor <input_file> <output_file>");
        std::process::exit(1);
    }

    let input_path = &args[1];
    let output_path = &args[2];

    let file = File::open(input_path).expect("Could not open input file");
    let reader = io::BufReader::new(file);

    let mut entries = Vec::new();
    for line in reader.lines() {
        if let Ok(l) = line {
            if let Ok(entry) = serde_json::from_str::<LogEntry>(&l) {
                entries.push(entry);
            }
        }
    }

    let mut total: f32 = 0.0;

    // BUG 1: Off-by-one error (<= instead of <)
    let mut i = 0;
    while i <= entries.len() {
        // BUG 2: Precision loss due to f32
        total += entries[i].sensor_val as f32;
        i += 1;
    }

    let metrics = Metrics {
        processed_count: entries.len(),
        total_sensor_value: total as f64,
    };

    let out_json = serde_json::to_string_pretty(&metrics).unwrap();
    let mut out_file = File::create(output_path).expect("Could not create output file");
    out_file.write_all(out_json.as_bytes()).unwrap();
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
