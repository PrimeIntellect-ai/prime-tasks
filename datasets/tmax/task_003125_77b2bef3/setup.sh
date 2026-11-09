#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user
    mkdir -p /app/vendored/fast_csv_reader/src

    cat << 'EOF' > /app/vendored/fast_csv_reader/Cargo.toml
[package]
name = "fast_csv_reader"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/vendored/fast_csv_reader/src/lib.rs
use std::io::{BufRead, BufReader, Read};

pub struct Reader<R> {
    reader: BufReader<R>,
}

impl<R: Read> Reader<R> {
    pub fn new(rdr: R) -> Self {
        Reader {
            reader: BufReader::new(rdr),
        }
    }

    pub fn next_record(&mut self) -> Option<Vec<String>> {
        let mut line = String::new();
        loop {
            line.clear();
            let bytes_read = self.reader.read_line(&mut line).ok()?;
            if bytes_read == 0 {
                return None;
            }
            let trimmed = line.trim_end();
            let cols: Vec<String> = trimmed.split(',').map(|s| s.to_string()).collect();
            if cols.len() == 3 {
                return Some(cols);
            }
        }
    }
}
EOF

    cat << 'EOF' > /tmp/generate_data.py
import csv
import json
import random
import math

random.seed(42)
readings = []
anomalies = []

ts = 1600000000
for i in range(1000):
    ts += 60
    val = 100.0 + math.sin(i * 0.1) * 10 + random.uniform(-2, 2)
    if i % 50 == 0 and i >= 10:
        val += 50.0
    readings.append((ts, val))

for i in range(len(readings)):
    if i >= 9:
        window = [r[1] for r in readings[i-9:i+1]]
        mean = sum(window) / 10
        variance = sum((x - mean) ** 2 for x in window) / 9
        std_dev = math.sqrt(variance)
        if abs(readings[i][1] - mean) > 3.0 * std_dev:
            anomalies.append(readings[i][0])

with open('/home/user/sensor_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'sensor_name', 'reading'])
    for ts, val in readings:
        writer.writerow([ts, "Turbine\nAlpha", f"{val:.4f}"])
    for i in range(200):
        writer.writerow([1600000000 + i*60, "Decoy", "50.0000"])

with open('/app/ground_truth_anomalies.json', 'w') as f:
    json.dump(anomalies, f)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
