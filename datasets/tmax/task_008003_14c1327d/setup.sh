#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl protobuf-compiler wget
    pip3 install pytest

    # Install grpcurl
    wget https://github.com/fullstorydev/grpcurl/releases/download/v1.8.7/grpcurl_1.8.7_linux_x86_64.tar.gz
    tar -xvf grpcurl_1.8.7_linux_x86_64.tar.gz
    mv grpcurl /usr/local/bin/
    rm grpcurl_1.8.7_linux_x86_64.tar.gz

    # Install Rust
    export CARGO_HOME=/opt/cargo
    export RUSTUP_HOME=/opt/rustup
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:${PATH}"
    echo 'export PATH="/opt/cargo/bin:${PATH}"' > /etc/profile.d/rust.sh

    useradd -m -s /bin/bash user || true

    # Create C artifact files
    mkdir -p /home/user/artifact/src
    cat << 'EOF' > /home/user/artifact/src/Makefile
app: main.c
    gcc -o app main.c
EOF

    cat << 'EOF' > /home/user/artifact/src/main.c
int main() {
    printf("Artifact Built\n")
    return 0;
}
EOF

    # Create Rust server files
    mkdir -p /home/user/artifact-server/src
    mkdir -p /home/user/artifact-server/proto

    cat << 'EOF' > /home/user/artifact-server/Cargo.toml
[package]
name = "artifact-server"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1.0", features = ["full", "macros", "rt-multi-thread"] }
tonic = "0.9"
prost = "0.11"

[build-dependencies]
tonic-build = "0.9"
EOF

    cat << 'EOF' > /home/user/artifact-server/build.rs
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::compile_protos("proto/build.proto")?;
    Ok(())
}
EOF

    cat << 'EOF' > /home/user/artifact-server/proto/build.proto
syntax = "proto3";
package build;

service BuildService {
  rpc GetStatus (StatusRequest) returns (StatusResponse);
}

message StatusRequest {
  string job_id = 1;
}

message StatusResponse {
  string status = 1;
}
EOF

    cat << 'EOF' > /home/user/artifact-server/src/main.rs
use axum::{routing::get, Router, extract::Path};
use std::net::SocketAddr;

mod grpc;

pub mod build {
    tonic::include_proto!("build");
}

async fn build_handler(Path(job_id): Path<String>) -> String {
    format!("Build started for {}", job_id)
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/build/:job_id", get(build_handler));

    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    println!("HTTP server listening on {}", addr);

    let grpc_addr = "[::]:50051".parse().unwrap();
    let grpc_service = build::build_service_server::BuildServiceServer::new(grpc::MyBuildService::default());

    tokio::spawn(async move {
        tonic::transport::Server::builder()
            .add_service(grpc_service)
            .serve(grpc_addr)
            .await
            .unwrap();
    });

    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}
EOF

    cat << 'EOF' > /home/user/artifact-server/src/grpc.rs
use tonic::{Request, Response, Status};
use crate::build::build_service_server::BuildService;
use crate::build::{StatusRequest, StatusResponse};

#[derive(Default)]
pub struct MyBuildService {}

#[tonic::async_trait]
impl BuildService for MyBuildService {
    async fn get_status(
        &self,
        _request: Request<StatusRequest>,
    ) -> Result<Response<StatusResponse>, Status> {
        Err(Status::unimplemented("Not yet implemented"))
    }
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /opt/cargo /opt/rustup
