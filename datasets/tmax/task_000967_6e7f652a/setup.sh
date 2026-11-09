#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo
pip3 install pytest

mkdir -p /home/user/data
mkdir -p /home/user/anomaly_detector/src

cat << 'EOF' > /home/user/data/metrics.log
Q101|120.5
Q102|110.0
Q101|125.0
Q103|90.5e
Q101|122.5
Q102|115.0
Q104|50.0
Q104|52.0
Q104|10.0
Q105|invalid
Q101|128.0
EOF

cat << 'EOF' > /home/user/anomaly_detector/Cargo.toml
[package]
name = "anomaly_detector"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /home/user/anomaly_detector/src/main.rs
use std::collections::HashMap;
use std::env;
use std::fs::File;
use std::io::{self, BufRead, Write};

#[derive(Default)]
struct Welford {
    count: f64,
    mean: f64,
    m2: f64,
}

impl Welford {
    fn update(&mut self, value: f64) {
        self.count += 1.0;
        let delta = value - self.mean;
        self.mean += delta / self.count;
        let delta2 = value - self.mean;
        self.m2 += delta * delta2;
    }

    fn variance(&self) -> f64 {
        // BUG: division by zero if count == 1.0
        self.m2 / (self.count - 1.0)
    }
}

fn parse_value(val_str: &str) -> f64 {
    // BUG: panics on "90.5e" or "invalid"
    if val_str.contains('e') {
        let parts: Vec<&str> = val_str.split('e').collect();
        let base: f64 = parts[0].parse().unwrap();
        let exp: i32 = parts[1].parse().unwrap(); // panics here if parts[1] is empty
        base * 10f64.powi(exp)
    } else {
        val_str.parse().unwrap() // panics here if not a float
    }
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <metrics_file>", args[0]);
        std::process::exit(1);
    }

    let file = File::open(&args[1])?;
    let reader = io::BufReader::new(file);

    let mut stats: HashMap<String, Welford> = HashMap::new();

    for line in reader.lines() {
        let line = line?;
        let parts: Vec<&str> = line.split('|').collect();
        if parts.len() == 2 {
            let qid = parts[0].to_string();
            // In a fixed version, parse_value should return Option/Result and skip on err
            let val = parse_value(parts[1]); 

            let w = stats.entry(qid).or_insert_with(Welford::default);
            w.update(val);
        }
    }

    let mut out = File::create("/home/user/corrected_queries.csv")?;
    writeln!(out, "query_id,count,mean,variance")?;

    let mut keys: Vec<&String> = stats.keys().collect();
    keys.sort();

    for k in keys {
        let w = &stats[k];
        writeln!(out, "{},{},{:.2},{:.2}", k, w.count, w.mean, w.variance())?;
    }

    Ok(())
}
EOF

cd /home/user/anomaly_detector && cargo build

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
