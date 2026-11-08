#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential protobuf-compiler pkg-config libssl-dev
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:$PATH"

    mkdir -p /home/user/grpc_refactor_pr/.github/workflows
    cd /home/user/grpc_refactor_pr

    cat << 'EOF' > Cargo.toml
[workspace]
members = ["client", "server"]
resolver = "2"
EOF

    cat << 'EOF' > .github/workflows/rust.yml
name: Rust CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Format
      run: cargo fmt --chek
    - name: Test
      run: cargo tesst
    - name: Build
      run: cargo buid --release
EOF

    cargo new --bin server
    mkdir -p server/proto

    cat << 'EOF' > server/Cargo.toml
[package]
name = "server"
version = "0.1.0"
edition = "2021"

[dependencies]
tonic = "0.10"
prost = "0.12"
tokio = { version = "1.0", features = ["macros", "rt-multi-thread"] }
client = { path = "../client" }

[build-dependencies]
tonic-build = "0.10"
EOF

    cat << 'EOF' > server/proto/service.proto
syntax = "proto3";
package processor;

service DataProcessor {
    rpc ProcessData (DataRequest) returns (DataResponse);
}

message DataRequest {
    int32 id = 1;
    string payload = 2;
    // Syntax error: missing semicolon
    bool is_active = 3
}

message DataResponse {
    bool success = 1;
    string message = 2;
}
EOF

    cat << 'EOF' > server/build.rs
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::compile_protos("proto/service.proto")?;
    Ok(())
}
EOF

    cat << 'EOF' > server/src/main.rs
use client::AppConfig;

pub mod processor {
    tonic::include_proto!("processor");
}

use processor::data_processor_server::{DataProcessor, DataProcessorServer};
use processor::{DataRequest, DataResponse};
use tonic::{transport::Server, Request, Response, Status};

#[derive(Default)]
pub struct MyProcessor {}

#[tonic::async_trait]
impl DataProcessor for MyProcessor {
    async fn process_data(
        &self,
        request: Request<DataRequest>,
    ) -> Result<Response<DataResponse>, Status> {
        let req = request.into_inner();
        let config = AppConfig { max_retries: 3 };

        Ok(Response::new(DataResponse {
            success: true,
            message: format!("Processed {} with config retries {}", req.payload, config.max_retries),
        }))
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "[::1]:50051".parse()?;
    let processor = MyProcessor::default();

    Server::builder()
        .add_service(DataProcessorServer::new(processor))
        .serve(addr)
        .await?;

    Ok(())
}
EOF

    cargo new --bin client

    cat << 'EOF' > client/Cargo.toml
[package]
name = "client"
version = "0.1.0"
edition = "2021"

[dependencies]
tonic = "0.10"
prost = "0.12"
tokio = { version = "1.0", features = ["macros", "rt-multi-thread"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
server = { path = "../server" }
EOF

    cat << 'EOF' > client/src/lib.rs
#[derive(serde::Deserialize, Debug)]
pub struct AppConfig {
    pub max_retries: u32,
}
EOF

    cat << 'EOF' > client/src/main.rs
use server::processor::data_processor_client::DataProcessorClient;
use server::processor::DataRequest;
use std::fs;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut client = DataProcessorClient::connect("http://[::1]:50051").await?;

    let data = fs::read_to_string("/home/user/grpc_refactor_pr/input.json")?;

    // TODO: parse JSON into DataRequest

    // let request = tonic::Request::new(parsed_req);
    // let response = client.process_data(request).await?;
    // println!("RESPONSE={}", response.into_inner().message);

    Ok(())
}
EOF

    cat << 'EOF' > input.json
{
    "id": 42,
    "payload": "secret_data_99",
    "is_active": true
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /opt/rust /opt/cargo
