#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/telemetry_app/data
    mkdir -p /home/user/telemetry_app/src

    cat << 'EOF' > /home/user/telemetry_app/Cargo.toml
[package]
name = "telemetry_app"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/telemetry_app/src/main.rs
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <log_file>", args[0]);
        std::process::exit(1);
    }

    let file = File::open(&args[1]).expect("Failed to open file");
    let reader = BufReader::new(file);

    let mut sum: f32 = 0.0;
    let mut count: u32 = 0;

    for line in reader.lines() {
        let line = line.unwrap();
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() != 3 {
            continue;
        }

        // This causes the panic on malformed lines
        let val: f32 = parts[2].trim().parse().unwrap(); 

        sum += val; 
        count += 1;
    }

    println!("Average: {}", sum / (count as f32));
}
EOF

    cat << 'EOF' > /home/user/telemetry_app/data/sensors.log
1610000000,sensorA,10000000.0
1610000001,sensorA,0.123456
1610000002,sensorA,ERR
1610000003,sensorA,0.876544
1610000004,sensorA,BAD_DATA
1610000005,sensorA,5000000.0
EOF

    chown -R user:user /home/user/telemetry_app
    chmod -R 777 /home/user
