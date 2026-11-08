#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/pipeline/src
    cd /home/user

    cat << 'EOF' > generate_data.py
import csv
with open('/home/user/data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['f1', 'f2', 'label'])
    for i in range(1, 1001):
        writer.writerow([float(i), float(i * 2), i % 2])
EOF
    python3 generate_data.py

    cat << 'EOF' > /home/user/pipeline/Cargo.toml
[package]
name = "pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.1"
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > /home/user/pipeline/src/main.rs
use std::error::Error;
use std::fs::File;
use std::time::Instant;

#[derive(serde::Deserialize)]
struct Record {
    f1: f64,
    f2: f64,
    label: i32,
}

fn main() -> Result<(), Box<dyn Error>> {
    let mut reader = csv::Reader::from_path("/home/user/data.csv")?;
    let mut records: Vec<Record> = Vec::new();
    for result in reader.deserialize() {
        records.push(result?);
    }

    // BUG: Computing stats on the entire dataset
    let n = records.len() as f64;
    let sum_f1: f64 = records.iter().map(|r| r.f1).sum();
    let sum_f2: f64 = records.iter().map(|r| r.f2).sum();
    let mean_f1 = sum_f1 / n;
    let mean_f2 = sum_f2 / n;

    let var_f1: f64 = records.iter().map(|r| (r.f1 - mean_f1).powi(2)).sum::<f64>() / (n - 1.0);
    let var_f2: f64 = records.iter().map(|r| (r.f2 - mean_f2).powi(2)).sum::<f64>() / (n - 1.0);
    let std_f1 = var_f1.sqrt();
    let std_f2 = var_f2.sqrt();

    let start = Instant::now();
    // In buggy version, we just output test set directly
    let mut wtr = csv::Writer::from_path("/home/user/test_transformed.csv")?;
    wtr.write_record(&["reduced_f", "label"])?;

    for r in records.iter().skip(800) {
        let f1_scaled = (r.f1 - mean_f1) / std_f1;
        let f2_scaled = (r.f2 - mean_f2) / std_f2;
        let reduced_f = (f1_scaled + f2_scaled) / 2.0;
        wtr.write_record(&[format!("{:.4}", reduced_f), r.label.to_string()])?;
    }
    wtr.flush()?;
    println!("Inference time: {:?}", start.elapsed());

    Ok(())
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
