#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        curl \
        build-essential \
        cmake \
        tesseract-ocr \
        libtesseract-dev \
        protobuf-compiler \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest protobuf Pillow

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /app/rust_lib/src

    # Create Rust library with borrow checker error
    cat << 'EOF' > /app/rust_lib/src/lib.rs
#[no_mangle]
pub extern "C" fn process_value(current_state: u64, value: u64) -> u64 {
    let mut state = current_state;
    let r1 = &state;
    let r2 = &mut state; // Error: cannot borrow as mutable because it is also borrowed as immutable
    *r2 = *r1 + value;
    *r2 * 2
}
EOF

    # Create Cargo.toml
    cat << 'EOF' > /app/rust_lib/Cargo.toml
[package]
name = "accum"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    # Create C wrapper
    cat << 'EOF' > /app/rust_lib/wrapper.c
#include <stdint.h>

extern uint64_t process_value(uint64_t current_state, uint64_t value);

uint64_t call_process_value(uint64_t current_state, uint64_t value) {
    return process_value(current_state, value);
}
EOF

    # Create CMakeLists.txt with missing link library
    cat << 'EOF' > /app/rust_lib/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(wrapper C)

add_library(wrapper SHARED wrapper.c)
# Intentionally missing: target_link_libraries(wrapper accum)
EOF

    # Create schema.png
    # ImageMagick policy fix to allow writing
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' /etc/ImageMagick-6/policy.xml || true
    convert -size 600x300 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,40 'syntax = \"proto3\";\nmessage Operations {\n  repeated uint64 values = 1;\n}'" /app/schema.png

    # Create hidden schema for oracle
    cat << 'EOF' > /app/schema.proto
syntax = "proto3";
message Operations {
  repeated uint64 values = 1;
}
EOF
    protoc --python_out=/app -I=/app /app/schema.proto

    # Create oracle
    cat << 'EOF' > /app/oracle
#!/usr/bin/env python3
import sys
import binascii
sys.path.insert(0, '/app')
import schema_pb2

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    hex_str = sys.argv[1]
    data = binascii.unhexlify(hex_str)
    ops = schema_pb2.Operations()
    ops.ParseFromString(data)

    state = 0
    for v in ops.values:
        state = (state + v) * 2
    print(state)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle

    # Make Rust available to all users
    chmod -R 777 /root/.cargo || true
    chmod -R 777 /root/.rustup || true
    ln -s /root/.cargo/bin/cargo /usr/local/bin/cargo
    ln -s /root/.cargo/bin/rustc /usr/local/bin/rustc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
