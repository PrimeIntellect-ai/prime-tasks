#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tshark strace cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/analyzer/src

    # Create a valid dummy pcap file
    echo "000000 00 00 00 00 00 00 00 00 00 00 00 00 08 00 45 00" > /tmp/dummy.hex
    text2pcap /tmp/dummy.hex "/home/user/data/capture 01.pcap"

    # Create .env
    cat << 'EOF' > /home/user/analyzer/.env
PCAP_FILTER=udp
EOF

    # Create Cargo.toml
    cat << 'EOF' > /home/user/analyzer/Cargo.toml
[package]
name = "analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
dotenv = "0.15"
EOF

    # Create main.rs
    cat << 'EOF' > /home/user/analyzer/src/main.rs
use std::process::Command;
use std::env;
use std::fs;

fn main() {
    dotenv::dotenv().ok();
    let filter = env::var("PCAP_FILTER").expect("PCAP_FILTER not set");
    let data_dir = "/home/user/data";

    for entry in fs::read_dir(data_dir).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();

        if path.is_file() && path.extension().unwrap_or_default() == "pcap" {
            let filename = path.to_str().unwrap();

            // BUG: Unquoted filename breaks on spaces
            let cmd = format!("tshark -r {} -Y '{}' -w /tmp/filtered.pcap", filename, filter);

            let status = Command::new("sh")
                .arg("-c")
                .arg(&cmd)
                .status()
                .expect("Failed to execute tshark");

            if !status.success() {
                panic!("Command failed for file: {}", filename);
            }
        }
    }
    fs::write("/home/user/success.log", "Processing complete.\n").unwrap();
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
