#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential protobuf-compiler
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /opt/rust /opt/cargo
    ln -s /opt/cargo/bin/* /usr/local/bin/

    mkdir -p /home/user/workspace/rs_app/src

    cat << 'EOF' > /home/user/workspace/checksum.c
#include <stdint.h>
#include <stddef.h>

uint32_t compute_fec(const uint8_t* data, size_t len) {
    uint32_t fec = 0x12345678;
    for (size_t i = 0; i < len; i++) {
        fec ^= data[i];
        fec = (fec << 5) | (fec >> 27);
    }
    return fec;
}
EOF

    cat << 'EOF' > /home/user/workspace/message.proto
syntax = "proto3";
package polyglot;

message MessageRecord {
    bytes payload = 1;
    uint32 fec = 2;
}
EOF

    cat << 'EOF' > /home/user/workspace/rs_app/Cargo.toml
[package]
name = "rs_app"
version = "0.1.0"
edition = "2021"

[dependencies]
prost = "0.12"

[build-dependencies]
prost-build = "0.12"
cc = "1.0"
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
