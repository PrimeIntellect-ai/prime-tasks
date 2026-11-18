#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc protobuf-compiler
    pip3 install pytest

    mkdir -p /home/user/api-gateway/proto
    mkdir -p /home/user/api-gateway/src

    cat << 'EOF' > /home/user/api-gateway/Cargo.toml
[package]
name = "api-gateway"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1.28", features = ["full"] }
# Intentional conflict: tonic 0.9 needs prost 0.11, but prost 0.12 is specified
tonic = "0.9"
prost = "0.12"
crc32fast = "1.3"
proptest = "1.2"

[build-dependencies]
tonic-build = "0.9"
EOF

    cat << 'EOF' > /home/user/api-gateway/build.rs
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::compile_protos("proto/gateway.proto")?;
    Ok(())
}
EOF

    cat << 'EOF' > /home/user/api-gateway/proto/gateway.proto
syntax = "proto3";
package gateway;

message ForwardRequest {
    string id = 1;
    bytes payload = 2;
}

message ForwardResponse {
    bool success = 1;
}

service Gateway {
    rpc Forward (ForwardRequest) returns (ForwardResponse);
}
EOF

    cat << 'EOF' > /home/user/api-gateway/src/main.rs
mod rest;
mod security_tests;

#[tokio::main]
async fn main() {
    // entrypoint stub
}
EOF

    cat << 'EOF' > /home/user/api-gateway/src/rest.rs
use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    body::Bytes,
};
use crc32fast::Hasher;

// Stub for gRPC client
pub async fn forward_to_grpc(id: String, payload: Bytes) -> Result<(), ()> {
    Ok(())
}

// TODO: Implement `relay_handler`
// pub async fn relay_handler(...) -> impl IntoResponse { ... }
EOF

    cat << 'EOF' > /home/user/api-gateway/src/security_tests.rs
#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    // TODO: Write proptests for the checksum validation logic
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
