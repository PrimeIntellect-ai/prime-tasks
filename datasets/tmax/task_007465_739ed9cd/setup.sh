#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo
    pip3 install pytest

    mkdir -p /home/user/mobile_build/data
    mkdir -p /home/user/mobile_build/scripts
    mkdir -p /home/user/mobile_build/tools/db_signer/src

    # Create v1.db
    sqlite3 /home/user/mobile_build/data/v1.db <<EOF
CREATE TABLE raw_metrics(id INTEGER PRIMARY KEY, ts INTEGER, val REAL);
INSERT INTO raw_metrics (id, ts, val) VALUES (1, 1000, 10.0);
INSERT INTO raw_metrics (id, ts, val) VALUES (2, 1005, 14.0);
INSERT INTO raw_metrics (id, ts, val) VALUES (3, 1010, 12.0);
INSERT INTO raw_metrics (id, ts, val) VALUES (4, 1015, 18.0);
INSERT INTO raw_metrics (id, ts, val) VALUES (5, 1020, 16.0);
EOF

    # Setup Cargo.toml for the Rust tool
    cat << 'EOF' > /home/user/mobile_build/tools/db_signer/Cargo.toml
[package]
name = "db_signer"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    # Create the broken Rust main.rs
    cat << 'EOF' > /home/user/mobile_build/tools/db_signer/src/main.rs
use std::env;
use std::fs;
use std::io::Write;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: db_signer <file>");
        std::process::exit(1);
    }
    let filename = args[1].clone();
    let content = fs::read(&filename).expect("Failed to read file");

    let mut hash: u32 = 0;
    for byte in content {
        hash = hash.wrapping_add(byte as u32);
    }

    let prefix = String::from("SIGNED_FILE_");
    let full_msg = prefix + &filename;

    // Borrow checker error: prefix was moved in the line above
    let label = prefix; 

    let out_name = format!("{}.sig", filename);
    let mut out_file = fs::File::create(out_name).expect("Failed to create sig file");
    write!(out_file, "LABEL:{}\nMSG:{}\nHASH:{}", label, full_msg, hash).unwrap();
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
