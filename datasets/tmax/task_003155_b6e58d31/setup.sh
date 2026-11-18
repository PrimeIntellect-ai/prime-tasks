#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y \
    python3 python3-pip \
    gcc binutils file curl \
    protobuf-compiler nginx \
    cargo rustc libssl-dev pkg-config

pip3 install pytest grpcio grpcio-tools

mkdir -p /app
cat << 'EOF' > /tmp/custom_crc.c
#include <stdint.h>
#include <stddef.h>

uint32_t calculate_crc(const uint8_t* data, uint64_t len, uint32_t init_val) {
    uint32_t hash = init_val;
    for (uint64_t i = 0; i < len; i++) {
        hash ^= data[i];
        hash *= 0x811C9DC5; 
    }
    return hash;
}
EOF
gcc -shared -fPIC -O2 -o /app/libcustom_crc.so /tmp/custom_crc.c
strip -s /app/libcustom_crc.so
rm /tmp/custom_crc.c

mkdir -p /home/user/crc_service/src /home/user/crc_service/proto
cat << 'EOF' > /home/user/crc_service/Cargo.toml
[package]
name = "crc_service"
version = "0.1.0"
edition = "2021"

[dependencies]
tonic = "0.10"
prost = "0.12"
tokio = { version = "1.0", features = ["macros", "rt-multi-thread"] }

[build-dependencies]
tonic-build = "0.10"
EOF

cat << 'EOF' > /home/user/crc_service/build.rs
fn main() {
    println!("cargo:rustc-link-search=native=/app");
    println!("cargo:rustc-link-lib=custom_crc");
    tonic_build::compile_protos("proto/crc.proto").unwrap_or_else(|e| panic!("Failed to compile protos: {}", e));
}
EOF

cat << 'EOF' > /home/user/crc_service/src/crc_ffi.rs
use std::os::raw::c_uchar;

extern "C" {
    // INTENTIONALLY BROKEN: Missing init_val, len is u32 instead of u64
    pub fn calculate_crc(data: *const c_uchar, len: u32) -> u32;
}
EOF

touch /home/user/crc_service/proto/crc.proto
touch /home/user/crc_service/src/main.rs
mkdir -p /home/user/proxy

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
