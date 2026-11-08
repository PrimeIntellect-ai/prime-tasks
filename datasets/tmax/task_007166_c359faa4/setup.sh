#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/uptime_stats/src
    mkdir -p /home/user/uptime_stats/data

    cat << 'EOF' > /home/user/uptime_stats/Cargo.toml
[package]
name = "uptime_stats"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/uptime_stats/src/main.rs
use std::fs::File;
use std::io::Read;
use std::thread;

fn main() {
    let mut file = File::open("data/latencies.bin").unwrap();
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer).unwrap();

    // Convert bytes to f32
    let mut latencies = Vec::new();
    for chunk in buffer.chunks_exact(4) {
        let val = f32::from_le_bytes(chunk.try_into().unwrap());
        latencies.push(val);
    }

    let num_threads = 4;
    let chunk_size = latencies.len() / num_threads;

    let mut handles = vec![];

    for i in 0..num_threads {
        let chunk = latencies[i * chunk_size..(i + 1) * chunk_size].to_vec();
        handles.push(thread::spawn(move || {
            let mut sum = 0.0f32;
            let mut sum_sq = 0.0f32;
            for &val in &chunk {
                sum += val;
                sum_sq += val * val;
            }
            (sum, sum_sq, chunk.len() as f32)
        }));
    }

    let mut total_sum = 0.0f32;
    let mut total_sum_sq = 0.0f32;
    let mut total_n = 0.0f32;

    for handle in handles {
        let (sum, sum_sq, n) = handle.join().unwrap();
        total_sum += sum;
        total_sum_sq += sum_sq;
        total_n += n;
    }

    let mean = total_sum / total_n;
    let variance = (total_sum_sq / total_n) - (mean * mean);

    println!("Mean: {:.4}", mean);
    println!("Variance: {:.4}", variance);
}
EOF

    cat << 'EOF' > /home/user/uptime_stats/data/generate.py
import struct

with open("/home/user/uptime_stats/data/latencies.bin", "wb") as f:
    for _ in range(5000001):
        f.write(struct.pack("<f", 100.1))
    for _ in range(5000002):
        f.write(struct.pack("<f", 99.9))
EOF

    python3 /home/user/uptime_stats/data/generate.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/uptime_stats
    chmod -R 777 /home/user
