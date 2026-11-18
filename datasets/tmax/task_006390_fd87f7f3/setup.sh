#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/pipeline/src

    # Generate deterministic dataset
    python3 -c "
import csv
with open('/home/user/data/interactions.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['user_id', 'feature_a', 'feature_b'])
    for i in range(1000):
        # Deterministic generation
        writer.writerow([f'u_{i}', float(i), float(i * 2.5)])
"

    # Create buggy Rust project
    cat << 'EOF' > /home/user/pipeline/Cargo.toml
[package]
name = "pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.2"
EOF

    cat << 'EOF' > /home/user/pipeline/src/main.rs
use std::error::Error;
// Buggy pipeline: data leakage
fn main() -> Result<(), Box<dyn Error>> {
    println!("Pipeline started.");
    Ok(())
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
