#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget gcc cargo protobuf-compiler
    pip3 install pytest

    # Install grpcurl
    wget https://github.com/fullstorydev/grpcurl/releases/download/v1.8.8/grpcurl_1.8.8_linux_x86_64.tar.gz
    tar -xzf grpcurl_1.8.8_linux_x86_64.tar.gz
    mv grpcurl /usr/local/bin/
    rm grpcurl_1.8.8_linux_x86_64.tar.gz

    # Create directories
    mkdir -p /home/user/legacy_math
    mkdir -p /home/user/grpc_service/src
    mkdir -p /home/user/grpc_service/proto

    # Create legacy math files
    cat << 'EOF' > /home/user/legacy_math/math_core.c
#include <stdint.h>

uint64_t compute_transform(uint64_t input) {
    // Proprietary math transform: a simple mock computation
    return (input * 937) ^ 0xABCDEF;
}
EOF

    cat << 'EOF' > /home/user/legacy_math/math_core.h
#include <stdint.h>
uint64_t compute_transform(uint64_t input);
EOF

    # Compile the C library
    gcc -shared -o /home/user/legacy_math/libmath_core.so -fPIC /home/user/legacy_math/math_core.c

    # Create Rust project files
    cat << 'EOF' > /home/user/grpc_service/Cargo.toml
[package]
name = "grpc_service"
version = "0.1.0"
edition = "2021"

[dependencies]
tonic = "0.10"
prost = "0.12"
tokio = { version = "1.32", features = ["macros", "rt-multi-thread"] }

[build-dependencies]
tonic-build = "0.10"
EOF

    cat << 'EOF' > /home/user/grpc_service/src/main.rs
fn main() {}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
