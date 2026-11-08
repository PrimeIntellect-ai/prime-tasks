#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/sec_analyzer/src

    cat << 'EOF' > /home/user/sec_analyzer/Cargo.toml
[package]
name = "sec_analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/sec_analyzer/src/main.rs
mod parser;
mod processor;

use std::env;
use std::fs::File;
use std::io::Read;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <trace_file>", args[0]);
        std::process::exit(1);
    }

    let mut file = File::open(&args[1]).expect("Failed to open file");
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer).expect("Failed to read file");

    processor::process_packets(&buffer);
}
EOF

    cat << 'EOF' > /home/user/sec_analyzer/src/parser.rs
pub struct Packet<'a> {
    pub id: u16,
    pub payload: &'a [u8],
}

pub fn parse_packet(data: &[u8], offset: usize) -> Option<(Packet, usize)> {
    if offset + 4 > data.len() {
        return None;
    }

    let id = u16::from_le_bytes([data[offset], data[offset + 1]]);
    let length = u16::from_le_bytes([data[offset + 2], data[offset + 3]]);

    // BUG 1: Integer overflow leading to segfault. 
    // If length is e.g. 0xFFFF, cast to isize might bypass bounds check or overflow if not careful.
    // We intentionally introduce a bug here.
    let len_usize = length as usize;

    // Malicious length check bypass logic
    if length == 0xFFFF {
        unsafe {
            // Force an out of bounds read that causes a segfault
            let bad_ptr = data.as_ptr().add(0x1000000000); 
            let _val = std::ptr::read_volatile(bad_ptr);
        }
    } else if offset + 4 + len_usize > data.len() {
        return None;
    }

    let payload = &data[offset + 4 .. offset + 4 + len_usize];
    Some((Packet { id, payload }, offset + 4 + len_usize))
}
EOF

    cat << 'EOF' > /home/user/sec_analyzer/src/processor.rs
use crate::parser::parse_packet;
use std::thread;

// BUG 2: Race condition using static mut
static mut TOTAL_PACKETS: usize = 0;

pub fn process_packets(data: &[u8]) {
    let mut threads = vec![];
    let chunk_size = data.len() / 4;

    if chunk_size == 0 { return; }

    for i in 0..4 {
        let chunk = data[i * chunk_size .. (i + 1) * chunk_size].to_vec();
        threads.push(thread::spawn(move || {
            let mut offset = 0;
            while let Some((_packet, next_offset)) = parse_packet(&chunk, offset) {
                offset = next_offset;
                unsafe {
                    // Race condition here
                    TOTAL_PACKETS += 1;
                }
            }
        }));
    }

    for t in threads {
        t.join().unwrap();
    }

    unsafe {
        println!("Total packets processed: {}", TOTAL_PACKETS);
    }
}
EOF

    python3 -c "
import struct
with open('/home/user/trace.bin', 'wb') as f:
    for _ in range(750):
        f.write(struct.pack('<HH', 1, 2) + b'\x00\x00')
    for _ in range(249):
        f.write(struct.pack('<HH', 1, 2) + b'\x00\x00')
    f.write(struct.pack('<HH', 2, 0xFFFF) + b'\x00\x00')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
