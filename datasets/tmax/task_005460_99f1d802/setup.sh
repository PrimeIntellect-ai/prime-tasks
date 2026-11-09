#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install Rust, Cargo, protobuf compiler, and curl
    apt-get install -y cargo rustc protobuf-compiler curl

    # Create directories
    mkdir -p /home/user/api-gateway/proto /home/user/api-gateway/src

    # Create Cargo.toml
    cat << 'EOF' > /home/user/api-gateway/Cargo.toml
[package]
name = "api-gateway"
version = "0.1.0"
edition = "2021"

[dependencies]
tonic = "0.9"
prost = "0.11"
tokio = { version = "1.0", features = ["macros", "rt-multi-thread"] }
warp = "0.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

[build-dependencies]
tonic-build = "0.9"
EOF

    # Create service.proto
    cat << 'EOF' > /home/user/api-gateway/proto/service.proto
syntax = "proto3";
package service;

message RecordRequest {
    integer id = 1;
}
message RecordResponse {
    string data = 1;
}

service GatewayService {
    rpc GetRecord (RecordRequest) returns (RecordResponse);
}
EOF

    # Create main.rs
    cat << 'EOF' > /home/user/api-gateway/src/main.rs
use warp::Filter;
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct Req { id: i32 }

#[derive(Serialize)]
struct Res { data: String }

fn get_record(id: i32) -> String {
    format!("Record {}", id)
}

#[tokio::main]
async fn main() {
    let api = warp::post()
        .and(warp::path("api"))
        .and(warp::path("record"))
        .and(warp::body::json())
        .map(|req: Req| {
            // Typo here
            let data = fetch_record(req.id);
            warp::reply::json(&Res { data })
        });

    warp::serve(api).run(([127, 0, 0, 1], 8080)).await;
}
EOF

    # Create the user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
