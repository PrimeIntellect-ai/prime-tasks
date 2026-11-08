#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ cargo
pip3 install pytest

# Create legacy binary
mkdir -p /app
cat << 'EOF' > /app/legacy_calc.cpp
#include <iostream>
#include <unordered_map>
#include <cstdint>
#include <iomanip>

int main() {
    std::unordered_map<uint32_t, double> sums;
    uint32_t id;
    double val;
    while (std::cin.read(reinterpret_cast<char*>(&id), sizeof(id))) {
        if (std::cin.read(reinterpret_cast<char*>(&val), sizeof(val))) {
            sums[id] += val;
        }
    }
    std::cout << "{";
    bool first = true;
    for (auto const& pair : sums) {
        if (!first) std::cout << ",";
        std::cout << "\"" << pair.first << "\":" << std::setprecision(17) << pair.second;
        first = false;
    }
    std::cout << "}\n";
    return 0;
}
EOF
g++ -O3 /app/legacy_calc.cpp -o /app/legacy_calc
strip -s /app/legacy_calc
rm /app/legacy_calc.cpp

# Create Rust project
mkdir -p /home/user/sensor_aggregator/src
cat << 'EOF' > /home/user/sensor_aggregator/Cargo.toml
[package]
name = "sensor_aggregator"
version = "0.1.0"
edition = "2021"

[dependencies]
serde_json = "1.0"
rayon = "1.5"
byteorder = "1.4"
EOF

cat << 'EOF' > /home/user/sensor_aggregator/src/main.rs
use std::env;
use std::fs::File;
use std::io::Read;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use rayon::prelude::*;
use byteorder::{LittleEndian, ReadBytesExt};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <file>", args[0]);
        return;
    }

    let mut file = File::open(&args[1]).unwrap();
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer).unwrap();

    let chunks: Vec<&[u8]> = buffer.chunks(12).collect();
    let sums = Arc::new(Mutex::new(HashMap::<u32, f32>::new()));

    chunks.par_iter().for_each(|chunk| {
        if chunk.len() == 12 {
            let mut rdr = std::io::Cursor::new(chunk);
            let id = rdr.read_u32::<LittleEndian>().unwrap();
            let val = rdr.read_f64::<LittleEndian>().unwrap() as f32; // Bug 1: Precision loss

            // Bug 2: Concurrency issue - unsafe bypass or dropped lock
            let mut map = sums.lock().unwrap();
            let count = map.entry(id).or_insert(0.0);
            *count += val;
        }
    });

    let map = sums.lock().unwrap();
    print!("{{");
    let mut first = true;
    for (k, v) in map.iter() {
        if !first { print!(","); }
        // Bug 3: Hardcoded precision
        print!("\"{}\":{:.4}", k, v);
        first = false;
    }
    println!("}}");
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
