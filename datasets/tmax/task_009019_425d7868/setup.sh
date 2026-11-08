#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/log_parser/src
    cd /home/user/log_parser

    cat << 'EOF' > Cargo.toml
[package]
name = "log_parser"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/main.rs
use std::fs::File;
use std::io::Read;

fn parse_i32(bytes: &[u8]) -> i32 {
    // Parse 32-bit signed integer (little endian)
    (bytes[0] as i32) + 
    (bytes[1] as i32) * 256 + 
    (bytes[2] as i32) * 65536 + 
    (bytes[3] as i32) * 16777216
}

fn parse_i64(bytes: &[u8]) -> i64 {
    let mut res = 0i64;
    for i in 0..8 {
        res |= (bytes[i] as i64) << (i * 8);
    }
    res
}

fn main() {
    let mut f = File::open("data.bin").unwrap();
    let mut header = [0u8; 12];
    f.read_exact(&mut header).unwrap();
    assert_eq!(&header[0..4], b"LOG1");
    let expected_total = parse_i64(&header[4..12]);

    let mut total: i32 = 0;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).unwrap();

    let mut i = 0;
    while i < buf.len() {
        let typ = buf[i];
        if typ == 1 {
            let val = parse_i32(&buf[i+1..i+5]);
            total += val;
        }
        i += 5;
    }

    assert_eq!(total as i64, expected_total, "Checksum mismatch!");
    std::fs::write("result.txt", format!("{}", total)).unwrap();
    println!("Success!");
}
EOF

    python3 -c "
import struct
total = 0
values = [1000000000, 2000000000, -500000000, 2000000000]
records = b''
for v in values:
    records += struct.pack('<Bi', 1, v)
    total += v

header = b'LOG1' + struct.pack('<q', total)
with open('data.bin', 'wb') as f:
    f.write(header)
    f.write(records)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
