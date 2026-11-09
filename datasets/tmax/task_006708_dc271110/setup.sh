#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc procps
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Setup Cargo project
    mkdir -p /home/user/data_pipeline/src
    cd /home/user/data_pipeline
    cargo init --bin 2>/dev/null

    # Generate sensor data
    cat << 'EOF' > /home/user/sensor_data.txt
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
5000.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
10.5
EOF

    # Create the broken main.rs
    cat << 'EOF' > /home/user/data_pipeline/src/main.rs
use std::fs;

fn main() {
    let content = fs::read_to_string("/home/user/sensor_data.txt").unwrap();
    let mut data: Vec<f64> = Vec::new();
    for line in content.lines() {
        let val: f64 = line.parse().unwrap();
        data.push(val);
    }

    // INTENTIONAL COMPILER ERROR: trying to sum f64 into i32
    let sum: i32 = data.iter().sum();
    let n = data.len() as f64;
    let mean = sum as f64 / n;

    // Let's use f64 for variance calculation
    let mean_f64 = data.iter().sum::<f64>() / n;

    let variance = data.iter().map(|value| {
        let diff = mean_f64 - *value;
        diff * diff
    }).sum::<f64>() / n;
    let std_dev = variance.sqrt();

    for val in data {
        if (val - mean_f64).abs() > 3.0 * std_dev {
            println!("{}", val);
        }
    }
}
EOF

    # Create the file holder script
    cat << 'EOF' > /home/user/file_holder.py
import os
import time

filepath = "/home/user/data_pipeline/src/main.rs"
fd = open(filepath, "r")
os.remove(filepath)

while True:
    time.sleep(10)
EOF

    # Ensure rustc and cargo are available for all users
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup

    # Create startup script to run the file holder process
    mkdir -p /.singularity.d/env
    cat << 'EOF' > /.singularity.d/env/99-start-holder.sh
if ! pgrep -f file_holder.py >/dev/null 2>&1; then
    python3 /home/user/file_holder.py >/dev/null 2>&1 &
    sleep 0.5
fi
export PATH="/home/user/.cargo/bin:${PATH}"
EOF
    chmod +x /.singularity.d/env/99-start-holder.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
