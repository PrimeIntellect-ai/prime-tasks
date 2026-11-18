#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Setup Oracle
    mkdir -p /app/oracle/src
    cat << 'EOF' > /app/oracle/src/main.rs
use std::io::{self, BufRead};
use std::collections::{HashMap, BTreeMap};

fn main() {
    let stdin = io::stdin();
    let mut data: HashMap<String, Vec<(u64, i32)>> = HashMap::new();

    for line in stdin.lock().lines() {
        let line = line.unwrap();
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() != 3 { continue; }
        let ts: u64 = parts[0].parse().unwrap();
        let sensor_id = parts[1].to_string();
        let value: i32 = parts[2].parse().unwrap();

        if value < 0 || value > 1000 {
            continue;
        }
        data.entry(sensor_id).or_insert_with(Vec::new).push((ts, value));
    }

    let mut results = Vec::new();
    for (sensor, records) in data {
        if records.is_empty() { continue; }
        let min_ts = records.iter().map(|(t, _)| *t).min().unwrap();
        let max_ts = records.iter().map(|(t, _)| *t).max().unwrap();
        let min_bucket = (min_ts / 60) * 60;
        let max_bucket = (max_ts / 60) * 60;

        let mut bucket_maxes: BTreeMap<u64, i32> = BTreeMap::new();
        for (ts, val) in records {
            let b = (ts / 60) * 60;
            let entry = bucket_maxes.entry(b).or_insert(val);
            if val > *entry { *entry = val; }
        }

        let mut last_val = 0;
        let mut curr_bucket = min_bucket;
        while curr_bucket <= max_bucket {
            if let Some(&val) = bucket_maxes.get(&curr_bucket) {
                last_val = val;
            }
            results.push((sensor.clone(), curr_bucket, last_val));
            curr_bucket += 60;
        }
    }

    results.sort_by(|a, b| {
        let cmp = a.0.cmp(&b.0);
        if cmp == std::cmp::Ordering::Equal {
            a.1.cmp(&b.1)
        } else {
            cmp
        }
    });

    for (sensor, bucket, val) in results {
        println!("REPORT: Sensor {} at {} has max value {}", sensor, bucket, val);
    }
}
EOF

    rustc -O /app/oracle/src/main.rs -o /app/oracle/etl_processor_oracle
    rm -rf /app/oracle/src

    # Setup Vendored Package
    mkdir -p /app/vendor/gap_filler/src
    cat << 'EOF' > /app/vendor/gap_filler/Cargo.toml
[package]
name = "gap_filler"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /app/vendor/gap_filler/src/lib.rs
pub fn init() {}
EOF

    cat << 'EOF' > /app/vendor/gap_filler/build.rs
fn main() {
    if std::env::var("GAP_FILL_BUILD_TOKEN").is_err() {
        panic!("Missing GAP_FILL_BUILD_TOKEN environment variable");
    }
}
EOF

    # Create user
    useradd -m -s /bin/bash user || true

    # Permissions
    chown -R user:user /app/vendor/gap_filler
    chmod -R 777 /app
    chmod -R 777 /home/user
