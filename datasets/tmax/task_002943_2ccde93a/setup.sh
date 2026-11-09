#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv cargo rustc
pip3 install pytest

mkdir -p /app/pow_shield/src

cat << 'EOF' > /app/pow_shield/Cargo.toml
[package]
name = "pow_shield"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /app/pow_shield/Makefile
all:
	cargo build --release
	cp target/release/libpow_shield.so ./
EOF

cat << 'EOF' > /app/pow_shield/src/lib.rs
#[no_mangle]
pub extern "C" fn verify_pow(data: *const u8, len: usize, nonce: u64, target: u32) -> bool {
    if data.is_null() || target == 0 {
        return false;
    }
    let slice = unsafe { std::slice::from_raw_parts(data, len) };

    // Perturbation: Borrow checker error (use after drop / invalid lifetime)
    let temp_vec = slice.to_vec();
    let ref_to_data = &temp_vec;
    drop(temp_vec);

    let mut sum: u64 = 0;
    for &byte in ref_to_data.iter() {
        sum += byte as u64;
    }

    (sum + nonce) % (target as u64) == 0
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
