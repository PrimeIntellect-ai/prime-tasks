#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest pandas

    mkdir -p /home/user/stats_service/src
    cd /home/user/stats_service

    cat << 'EOF' > Cargo.toml
[package]
name = "stats_service"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.2.2"
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > src/main.rs
use std::error::Error;
use std::fs::File;

fn main() -> Result<(), Box<dyn Error>> {
    let file = File::open("/home/user/data.csv")?;
    let mut rdr = csv::ReaderBuilder::new().has_headers(false).from_reader(file);

    let mut numbers: Vec<i32> = Vec::new();

    // Memory leak / excessive memory usage: storing everything
    for result in rdr.records() {
        let record = result?;
        let val: i32 = record[0].parse()?;
        numbers.push(val);
    }

    let mut sum: i32 = 0;
    let mut sum_sq: i32 = 0;
    let mut count: i32 = 0;

    for &num in &numbers {
        sum += num;
        sum_sq += num * num; // Integer overflow happens here
        count += 1;
    }

    let mean = sum as f64 / count as f64;
    let variance = (sum_sq as f64 / count as f64) - (mean * mean);

    println!("Mean: {}", mean);
    println!("Variance: {}", variance);

    Ok(())
}
EOF

    python3 -c '
import random
random.seed(42)
with open("/home/user/data.csv", "w") as f:
    for _ in range(100000):
        # Mean 10000, stddev roughly 500
        val = int(random.gauss(10000, 500))
        f.write(f"{val}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
