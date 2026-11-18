#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tshark cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ingester_diag/ingester/src

    cat << 'EOF' > /home/user/ingester_diag/service.log
[INFO] Starting ingestion service...
[INFO] Listening for raw hex payloads on stdin...
thread 'main' panicked at 'called `Result::unwrap()` on an `Err` value: FromUtf8Error { bytes: [87, 65, 82, 78, 58, 32, 68, 105, 115, 107, 32, 255, 32, 101, 114, 114, 111, 114], error: Utf8Error { valid_up_to: 11, error_len: Some(1) } }', src/main.rs:14:45
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
EOF

    cat << 'EOF' > /home/user/ingester_diag/run.sh
#!/bin/bash
export TARGET_PORT=8000 # BUG: The actual traffic is on UDP port 9000

# TODO: Use tshark to extract the udp payload (data field) from traffic.pcap for TARGET_PORT
# and pipe the hex output to the Rust ingester.
# Example: tshark -r traffic.pcap -Y "udp.port == $TARGET_PORT" -T fields -e data | cargo run --manifest-path ingester/Cargo.toml
EOF
    chmod +x /home/user/ingester_diag/run.sh

    cat << 'EOF' > /home/user/ingester_diag/ingester/Cargo.toml
[package]
name = "ingester"
version = "0.1.0"
edition = "2021"

[dependencies]
hex = "0.4"
EOF

    cat << 'EOF' > /home/user/ingester_diag/ingester/src/main.rs
use std::io::{self, BufRead};

fn main() {
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        if line.trim().is_empty() {
            continue;
        }

        let bytes = hex::decode(line.trim()).expect("Invalid hex");
        // BUG: unwrap() causes panic on invalid UTF-8
        let message = String::from_utf8(bytes).unwrap();

        println!("LOG: {}", message);
    }
}
EOF

    cat << 'EOF' > /tmp/make_pcap.py
import struct

def write_pcap(filename):
    with open(filename, 'wb') as f:
        # PCAP Global Header
        f.write(struct.pack('<IHHiIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))

        payloads = [
            b"INFO: System start",
            b"WARN: Disk \xff error",
            b"INFO: System stop"
        ]

        for p in payloads:
            # UDP header: src port 1234, dst port 9000, length, checksum (0)
            udp_len = 8 + len(p)
            udp_hdr = struct.pack('!HHHH', 1234, 9000, udp_len, 0)

            # IPv4 header: ...
            ip_len = 20 + udp_len
            ip_hdr = struct.pack('!BBHHHBBH4s4s', 0x45, 0, ip_len, 0, 0, 64, 17, 0, b'\x7f\x00\x00\x01', b'\x7f\x00\x00\x01')

            # Ethernet header
            eth_hdr = b'\x00'*12 + b'\x08\x00'

            packet = eth_hdr + ip_hdr + udp_hdr + p

            # PCAP Record Header
            f.write(struct.pack('<IIII', 0, 0, len(packet), len(packet)))
            f.write(packet)

write_pcap('/home/user/ingester_diag/traffic.pcap')
EOF

    python3 /tmp/make_pcap.py

    chmod -R 777 /home/user
