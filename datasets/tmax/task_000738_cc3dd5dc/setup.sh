#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential
    pip3 install pytest pandas

    mkdir -p /app/backup-analyzer/src
    mkdir -p /home/user

    cat << 'EOF' > /app/backup-analyzer/Cargo.toml
[package]
name = "backup-analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
polars = { version = "0.32" }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /app/backup-analyzer/src/main.rs
use polars::prelude::*;
use serde::Deserialize;
use std::fs::File;
use std::io::{BufRead, BufReader};

#[derive(Deserialize, Debug, Clone)]
struct Record {
    cluster_id: String,
    timestamp: String,
    size_bytes: u64,
    duration_seconds: f64,
    status: String,
}

fn main() {
    // Naive O(N^2) implementation
    let file = File::open("/home/user/backup_logs.jsonl").unwrap();
    let reader = BufReader::new(file);
    let mut records = Vec::new();
    for line in reader.lines() {
        let rec: Record = serde_json::from_str(&line.unwrap()).unwrap();
        records.push(rec);
    }

    let mut anomalies = Vec::new();
    for i in 0..records.len() {
        let rec = &records[i];
        let mut count = 0;
        let mut sum = 0.0;
        for j in (0..=i).rev() {
            if records[j].cluster_id == rec.cluster_id {
                sum += records[j].duration_seconds;
                count += 1;
                if count == 7 {
                    let avg = sum / 7.0;
                    if rec.duration_seconds > 2.5 * avg {
                        anomalies.push((rec.cluster_id.clone(), rec.timestamp.clone(), rec.duration_seconds, avg));
                    }
                    break;
                }
            }
        }
    }
    // write anomalies...
}
EOF

    cat << 'EOF' > /app/generate_data.py
import json
import random
import csv

clusters = [f"cluster_{i}" for i in range(50)]
records = []
anomalies = []

for c in clusters:
    history = []
    for i in range(1000):
        duration = random.uniform(10.0, 50.0)
        if len(history) >= 7:
            avg = sum(history[-7:]) / 7.0
            if random.random() < 0.01:
                duration = avg * 3.0
                anomalies.append({
                    "cluster_id": c,
                    "timestamp": f"2023-01-01T{i:05d}Z",
                    "duration_seconds": duration,
                    "rolling_avg": avg
                })
        history.append(duration)
        records.append({
            "cluster_id": c,
            "timestamp": f"2023-01-01T{i:05d}Z",
            "size_bytes": 1024,
            "duration_seconds": duration,
            "status": "success"
        })

with open("/home/user/backup_logs.jsonl", "w") as f:
    for r in records:
        f.write(json.dumps(r) + "\n")

anomalies.sort(key=lambda x: x["timestamp"], reverse=True)
with open("/app/expected_anomalies.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["cluster_id", "timestamp", "duration_seconds", "rolling_avg"])
    writer.writeheader()
    for a in anomalies:
        writer.writerow(a)
EOF

    python3 /app/generate_data.py

    cat << 'EOF' > /app/verify_perf.py
import sys
print("Verification script")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
