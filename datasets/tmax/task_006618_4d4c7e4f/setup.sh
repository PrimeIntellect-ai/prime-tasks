#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/packet_parser/src
    cd /home/user/packet_parser

    cat << 'EOF' > Cargo.toml
[package]
name = "packet_parser"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/main.rs
use std::fs::File;
use std::io::{Read, Write};

fn main() {
    let mut file = File::open("capture.dat").expect("Failed to open capture.dat");
    let mut header = [0u8; 4];
    file.read_exact(&mut header).unwrap();

    if &header != b"PCAP" {
        panic!("Invalid header");
    }

    let mut dump = File::create("crash_dump.bin").unwrap();

    loop {
        let mut seq_bytes = [0u8; 2];
        if file.read_exact(&mut seq_bytes).is_err() {
            break;
        }
        let seq = u16::from_be_bytes(seq_bytes);

        let mut len_bytes = [0u8; 2];
        file.read_exact(&mut len_bytes).unwrap();
        let len = u16::from_be_bytes(len_bytes);

        let mut payload = vec![0u8; len as usize];
        file.read_exact(&mut payload).unwrap();

        // INTENTIONAL BUILD ERROR: Attempting to borrow payload immutably after moving it
        let payload_str = String::from_utf8(payload).unwrap();

        if payload_str.contains("MALFORMED") {
            // Write internal state to dump before panicking
            let err_msg = format!("FATAL_ERR_SEQ_{}", seq);
            dump.write_all(err_msg.as_bytes()).unwrap();
            dump.write_all(b"\x00\x00\x00\x00").unwrap();

            // Build error triggered here: payload was moved into String::from_utf8
            dump.write_all(&payload).unwrap();

            panic!("Encountered malformed packet!");
        }
    }
}
EOF

    python3 -c '
import struct

with open("capture.dat", "wb") as f:
    f.write(b"PCAP")

    # Packet 1
    p1 = b"NORMAL_TRAFFIC_1"
    f.write(struct.pack(">H", 1))
    f.write(struct.pack(">H", len(p1)))
    f.write(p1)

    # Packet 2 (The Malformed one, Seq 42)
    p2 = b"MALFORMED_DATA_FRAG"
    f.write(struct.pack(">H", 42))
    f.write(struct.pack(">H", len(p2)))
    f.write(p2)

    # Packet 3
    p3 = b"NORMAL_TRAFFIC_2"
    f.write(struct.pack(">H", 43))
    f.write(struct.pack(">H", len(p3)))
    f.write(p3)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
