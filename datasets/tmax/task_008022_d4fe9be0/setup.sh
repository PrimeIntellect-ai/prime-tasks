#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/wal_processor/src
    mkdir -p /home/user/wal_processor/.cargo

    cat << 'EOF' > /home/user/wal_processor/.cargo/config.toml
[build]
rustflags = ["--invalid-flag-that-breaks-build"]
EOF

    cat << 'EOF' > /home/user/wal_processor/Cargo.toml
[package]
name = "wal_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
byteorder = "1.4.3"
# Conflict: invalid dependency requirement
anyhow = "=1.0.9999" 
EOF

    cat << 'EOF' > /home/user/wal_processor/src/main.rs
use std::fs::File;
use std::io::{Read, Write};
use byteorder::{LittleEndian, ReadBytesExt};

fn main() {
    let mut file = File::open("/home/user/wal.dat").expect("Failed to open wal.dat");

    let mut count = 0.0;
    let mut sum = 0.0;
    let mut sum_sq = 0.0;

    loop {
        let mut id_bytes = [0u8; 4];
        let bytes_read = file.read(&mut id_bytes).unwrap_or(0);
        if bytes_read == 0 {
            break; // EOF
        }
        if bytes_read < 4 {
            panic!("Corrupted WAL: partial ID read");
        }

        let _id = u32::from_le_bytes(id_bytes);

        // This will panic on the truncated last record
        let val = file.read_f64::<LittleEndian>().expect("Corrupted WAL: missing value");

        count += 1.0;
        sum += val;
        sum_sq += val * val;
    }

    // Naive variance formula: E[X^2] - (E[X])^2
    // Suffers from catastrophic cancellation for values with low variance but high magnitude
    let mean = sum / count;
    let variance = (sum_sq / count) - (mean * mean);

    let mut out = File::create("/home/user/result.txt").unwrap();
    write!(out, "{:.6}", variance).unwrap();
}
EOF

    python3 -c '
import struct

with open("/home/user/wal.dat", "wb") as f:
    f.write(struct.pack("<I", 1))
    f.write(struct.pack("<d", 10000000.1))

    f.write(struct.pack("<I", 2))
    f.write(struct.pack("<d", 10000000.2))

    f.write(struct.pack("<I", 3))
    f.write(struct.pack("<d", 10000000.3))

    # Truncated record (only ID, no float)
    f.write(struct.pack("<I", 4))
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/wal_processor
    chown user:user /home/user/wal.dat
    chmod -R 777 /home/user
