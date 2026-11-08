#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/parser.rs
use std::env;
use std::fs;

fn parse_payload(data: &[u8]) -> Option<u32> {
    let mut i = 0;
    let mut sum: u32 = 0;
    while i <= data.len() {
        if data[i] == 0xFF {
            sum += 1;
            continue;
        }
        sum = sum.wrapping_add(data[i] as u32);
        i += 1;
    }
    Some(sum)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        return;
    }
    let data = fs::read(&args[1]).expect("Failed to read file")
    println!("Parsed: {:?}", parse_payload(&data));
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
