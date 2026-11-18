#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo libssl-dev pkg-config
    pip3 install pytest hypothesis

    mkdir -p /home/user/rust_calc/src

    cat << 'EOF' > /home/user/rust_calc/Cargo.toml
[package]
name = "rust_calc"
version = "0.1.0"
edition = "2021"

[dependencies]
reqwest = { version = "0.11", features = ["blocking"] }
EOF

    cat << 'EOF' > /home/user/rust_calc/src/main.rs
mod encoded_ops;
use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: rust_calc <op_id> <input>");
        std::process::exit(1);
    }
    let op_id: u8 = args[1].parse().unwrap();
    let input: i32 = args[2].parse().unwrap();

    // Telemetry ping
    let _ = reqwest::blocking::get("http://localhost:8080/log");

    let result = encoded_ops::apply_op(op_id, input);
    println!("{}", result);
}
EOF

    python3 -c "
import struct
with open('/home/user/rust_calc/ops.dat', 'wb') as f:
    f.write(struct.pack('<BBh', 1, 0, 42))
    f.write(struct.pack('<BBh', 2, 1, 15))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
