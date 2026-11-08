#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline/src

    cat << 'EOF' > /home/user/raw_data.csv
f1,f2,f3,f4
10.0,50.0,1.0,A
,60.0,2.0,B
20.0,150.0,3.0,C
30.0,40.0,4.0,D
EOF

    cat << 'EOF' > /home/user/pipeline/Cargo.toml
[package]
name = "pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/pipeline/src/main.rs
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn main() {
    let file = File::open("/home/user/raw_data.csv").unwrap();
    let reader = BufReader::new(file);
    let mut lines = reader.lines();

    let header = lines.next().unwrap().unwrap();
    let mut records = Vec::new();

    let mut sum_f1 = 0.0;
    let mut count_f1 = 0;

    for line in lines {
        let l = line.unwrap();
        let parts: Vec<&str> = l.split(',').collect();
        let f1_str = parts[0];
        let f2: f64 = parts[1].parse().unwrap();
        let f3: f64 = parts[2].parse().unwrap();
        let f4 = parts[3].to_string();

        let mut f1_val = None;
        if !f1_str.is_empty() {
            let val: f64 = f1_str.parse().unwrap();
            f1_val = Some(val);
            sum_f1 += val;
            count_f1 += 1;
        }

        records.push((f1_val, f2, f3, f4));
    }

    // BUG 1: Imputes with 0.0 instead of mean
    let f1_mean = 0.0;

    let mut out_file = File::create("/home/user/processed_data.csv").unwrap();
    // BUG 3: Dimensionality reduction is incomplete (kept f4, f1, f2 logic missing)
    writeln!(out_file, "f_new,f3,f4").unwrap();

    for (f1, f2, f3, f4) in records {
        let f1_final = f1.unwrap_or(f1_mean);

        // BUG 2: Incorrect outlier filter
        if f2 < 100.0 {
            continue;
        }

        let f_new = f1_final * f2;
        writeln!(out_file, "{},{},{}", f_new, f3, f4).unwrap();
    }
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
