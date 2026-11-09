#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc espeak
    pip3 install pytest

    mkdir -p /app

    # Generate audio file
    espeak -w /app/loc_config.wav "The offset for region ES is plus 3600. The offset for region DE is plus 7200. The offset for region BR is minus 10800."

    # Write oracle source
    cat << 'EOF' > /app/oracle.rs
use std::io::{self, BufRead};
use std::collections::HashMap;

fn main() {
    let mut offsets = HashMap::new();
    offsets.insert("ES".to_string(), 3600i64);
    offsets.insert("DE".to_string(), 7200i64);
    offsets.insert("BR".to_string(), -10800i64);

    let stdin = io::stdin();
    let mut records = Vec::new();

    for line in stdin.lock().lines() {
        let line = line.unwrap();
        if line.trim().is_empty() { continue; }
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() != 4 { continue; }

        let ts: i64 = parts[0].parse().unwrap();
        let region = parts[1].to_string();
        let key = parts[2].to_string();
        let count: i32 = parts[3].parse().unwrap();

        if let Some(&offset) = offsets.get(&region) {
            records.push((region, ts + offset, key, count));
        }
    }

    records.sort_by(|a, b| {
        a.0.cmp(&b.0)
           .then_with(|| b.1.cmp(&a.1))
           .then_with(|| a.2.cmp(&b.2))
    });

    for r in records {
        println!("{},{},{},{}", r.0, r.1, r.2, r.3);
    }
}
EOF

    # Compile oracle
    rustc /app/oracle.rs -o /app/oracle_processor
    chmod +x /app/oracle_processor

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/src
    chmod -R 777 /home/user
