#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/pipeline/src

    cat << 'EOF' > /home/user/pipeline/Cargo.toml
[package]
name = "etl_pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.3.0"
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > /home/user/pipeline/src/main.rs
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn main() {
    let input = File::open("input.csv").unwrap();
    let reader = BufReader::new(input);

    let mut output = File::create("cleaned.csv").unwrap();
    writeln!(output, "timestamp,distance").unwrap();

    // BUG: Breaks on embedded newlines, splits by comma naively
    for line in reader.lines().skip(1) {
        if let Ok(l) = line {
            let parts: Vec<&str> = l.split(',').collect();
            if parts.len() == 4 {
                let timestamp = parts[0];
                let x: f64 = parts[2].parse().unwrap_or(0.0);
                let y: f64 = parts[3].parse().unwrap_or(0.0);

                let distance = (x*x + y*y).sqrt();
                if distance <= 50.0 {
                    writeln!(output, "{},{:.2}", timestamp, distance).unwrap();
                }
            }
        }
    }
}
EOF

    cat << 'EOF' > /home/user/pipeline/input.csv
timestamp,location_notes,x,y
1000,"Sector A",10.0,20.0
1001,"Sector B
Warning: wet conditions",15.0,25.0
1002,"Sector C",100.0,100.0
1003,"Sector D",5.0,5.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
