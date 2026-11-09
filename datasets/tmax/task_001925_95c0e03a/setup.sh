#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils cargo rustc
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/diagnostic_workspace/lib
    mkdir -p /home/user/diagnostic_workspace/pcap_ingest/src

    cat << 'EOF' > /home/user/diagnostic_workspace/lib/telemetry.c
void init_telemetry() {}
EOF
    gcc -c /home/user/diagnostic_workspace/lib/telemetry.c -o /home/user/diagnostic_workspace/lib/telemetry.o
    ar rcs /home/user/diagnostic_workspace/lib/libtelemetry.a /home/user/diagnostic_workspace/lib/telemetry.o
    rm /home/user/diagnostic_workspace/lib/telemetry.c /home/user/diagnostic_workspace/lib/telemetry.o

    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *

pkts = []
# Packet 1: Valid JSON
pkts.append(Ether()/IP(src="192.168.1.1", dst="10.0.0.1")/UDP(sport=1234, dport=8080)/Raw(load=b'{"event":"login","user":"admin"}'))
# Packet 2: Valid JSON
pkts.append(Ether()/IP(src="192.168.1.2", dst="10.0.0.1")/UDP(sport=1235, dport=8080)/Raw(load=b'{"event":"click","item":"14"}'))
# Packet 3: Valid JSON
pkts.append(Ether()/IP(src="192.168.1.3", dst="10.0.0.1")/UDP(sport=1236, dport=8080)/Raw(load=b'{"event":"logout","user":"admin"}'))
# Packet 4: Malformed Payload (Invalid UTF-8 / Binary garbage causing json panic)
pkts.append(Ether()/IP(src="192.168.1.4", dst="10.0.0.1")/UDP(sport=1237, dport=8080)/Raw(load=b'\xff\xfe\xba\xad\xf0\x0d\x00\x00'))
# Packet 5: Valid JSON
pkts.append(Ether()/IP(src="192.168.1.5", dst="10.0.0.1")/UDP(sport=1238, dport=8080)/Raw(load=b'{"event":"login","user":"guest"}'))

wrpcap("/home/user/diagnostic_workspace/capture.pcap", pkts)
EOF
    python3 /tmp/gen_pcap.py

    cat << 'EOF' > /home/user/diagnostic_workspace/pcap_ingest/Cargo.toml
[package]
name = "pcap_ingest"
version = "0.1.0"
edition = "2021"

[dependencies]
pcap-file = "2.0.0"
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/diagnostic_workspace/pcap_ingest/build.rs
fn main() {
    println!("cargo:rustc-link-lib=static=telemetry");
    // BUG: Missing the search path:
    // println!("cargo:rustc-link-search=native=/home/user/diagnostic_workspace/lib");
}
EOF

    cat << 'EOF' > /home/user/diagnostic_workspace/pcap_ingest/src/main.rs
use pcap_file::pcap::PcapReader;
use std::fs::File;

extern "C" {
    fn init_telemetry();
}

fn main() {
    unsafe { init_telemetry(); }

    let file = File::open("../capture.pcap").expect("Failed to open pcap");
    let mut reader = PcapReader::new(file).expect("Failed to create reader");

    let mut count = 0;
    while let Some(pkt) = reader.next_packet() {
        let pkt = pkt.expect("Failed to read packet");
        count += 1;

        // Very basic extraction of UDP payload assuming Eth(14) + IP(20) + UDP(8) = 42 bytes header
        if pkt.data.len() > 42 {
            let payload = &pkt.data[42..];
            // Will panic on invalid UTF-8 / bad JSON
            let _val: serde_json::Value = serde_json::from_slice(payload).expect("Serialization error! Payload must be valid JSON UTF-8");
        }
    }
    println!("Processed {} packets successfully.", count);
}
EOF

    chown -R user:user /home/user/diagnostic_workspace
    chmod -R 777 /home/user
