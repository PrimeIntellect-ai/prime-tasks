#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /home/user/rust_lib/src
    mkdir -p /home/user/grpc

    cat << 'EOF' > /home/user/rust_lib/Cargo.toml
[package]
name = "rust_lib"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/rust_lib/src/lib.rs
// BROKEN RUST CODE - missing #[no_mangle], extern "C", and proper raw pointers
pub fn compute_checksum(data: &[u8]) -> u16 {
    let mut sum: u32 = 0;
    for &b in data {
        sum += b as u32;
    }
    (sum % 65536) as u16
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
