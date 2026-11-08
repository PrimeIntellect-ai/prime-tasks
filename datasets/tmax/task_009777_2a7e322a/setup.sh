#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the Rust project
    cargo new beacon_parser
    cd beacon_parser

    # Write the buggy Rust code
    cat << 'EOF' > src/main.rs
use std::env;
use std::fs::File;
use std::io::Read;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <payload_file>", args[0]);
        std::process::exit(1);
    }

    let mut file = File::open(&args[1]).expect("Failed to open file");
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer).expect("Failed to read file");

    let mut offset = 0;
    let mut frame_index = 0;

    while offset < buffer.len() {
        // Check magic bytes "C2BC"
        if offset + 4 > buffer.len() || &buffer[offset..offset+4] != b"C2BC" {
            println!("Invalid magic at offset {}", offset);
            break;
        }
        offset += 4;

        // Frame Type
        let _frame_type = buffer[offset];
        offset += 1;

        // Length (Little Endian)
        let length = u16::from_le_bytes([buffer[offset], buffer[offset+1]]) as usize;
        offset += 2;

        // BUG: This will panic if offset + length > buffer.len()
        let _data = &buffer[offset..offset+length];

        println!("Parsed frame {} with length {}", frame_index, length);

        offset += length;
        frame_index += 1;
    }
}
EOF

    # Generate payload.bin
    cd /home/user
    cat << 'EOF' > generate_payload.py
import struct

with open("payload.bin", "wb") as f:
    for i in range(500):
        # Magic
        f.write(b"C2BC")

        if i == 423:
            # Anomalous frame: Length 50000, but we only append a few bytes
            f.write(struct.pack("<B", 1)) # Type
            f.write(struct.pack("<H", 50000)) # Length
            f.write(b"A" * 10) # Data (cut short)
            break
        else:
            # Normal frame: Length 5
            f.write(struct.pack("<B", 1)) # Type
            f.write(struct.pack("<H", 5)) # Length
            f.write(b"A" * 5) # Data

EOF
    python3 generate_payload.py
    rm generate_payload.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
