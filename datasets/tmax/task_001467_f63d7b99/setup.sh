#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl libpcap-dev
    pip3 install pytest scapy

    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /home/user/telemetry_processor/src
    mkdir -p /home/user/logs
    mkdir -p /home/user/data
    mkdir -p /app

    # Create the legacy oracle
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    char *hex = argv[1];
    int len = strlen(hex);
    if (len < 6) return 1;

    unsigned char bytes[3];
    for (int i = 0; i < 3; i++) {
        sscanf(hex + 2*i, "%2hhx", &bytes[i]);
    }

    double score = (bytes[0] ^ 0x5A) * 2.5 + (bytes[1] << 2) - sqrt(bytes[2]);
    printf("%f\n", score);
    return 0;
}
EOF
    gcc -O3 -o /app/legacy_oracle /tmp/legacy.c -lm
    strip /app/legacy_oracle

    # Create Rust project
    cat << 'EOF' > /home/user/telemetry_processor/Cargo.toml
[package]
name = "telemetry_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
pcap = "1.1.0"
EOF

    cat << 'EOF' > /home/user/telemetry_processor/src/main.rs
mod worker;
mod formula;

use std::thread;

fn main() {
    let data = vec![1, 2, 3];
    let handle = thread::spawn(|| {
        println!("Processing: {:?}", data);
    });
    handle.join().unwrap();
}
EOF

    cat << 'EOF' > /home/user/telemetry_processor/src/worker.rs
use std::sync::Mutex;
use std::collections::HashMap;

pub struct Worker {
    pub state: Mutex<HashMap<u32, f64>>,
}
EOF

    cat << 'EOF' > /home/user/telemetry_processor/src/formula.rs
pub fn compute_score(bytes: &[u8]) -> f64 {
    // BUG: Index out of bounds
    let val = bytes[100];
    (bytes[0] & 0x5A) as f64 * 2.0 + (bytes[1] << 1) as f64 - (bytes[2] as f64).sqrt()
}
EOF

    # Create crash log
    cat << 'EOF' > /home/user/logs/processor_crash.log
thread 'main' panicked at 'index out of bounds: the len is 16 but the index is 100', src/formula.rs:3:15
stack backtrace:
   0: rust_begin_unwind
   1: core::panicking::panic_fmt
   2: core::panicking::panic_bounds_check
   3: telemetry_processor::formula::compute_score
EOF

    # Create PCAP file
    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import wrpcap, Ether, IP, UDP, Raw
import os

packets = []
for i in range(10):
    payload = bytes([i % 256, (i+1) % 256, (i+2) % 256] + [0]*13)
    pkt = Ether()/IP(dst="192.168.1.1")/UDP(dport=1234)/Raw(load=payload)
    packets.append(pkt)
wrpcap("/home/user/data/ingress.pcap", packets)
EOF
    python3 /tmp/gen_pcap.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
