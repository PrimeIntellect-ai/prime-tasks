#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential musl-tools jq
    pip3 install pytest

    # Install Rust system-wide
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    export PATH=/usr/local/cargo/bin:$PATH

    # Symlink binaries so they are in standard PATH
    ln -s /usr/local/cargo/bin/* /usr/local/bin/

    # Add musl target
    rustup target add x86_64-unknown-linux-musl

    # Create project directory and files
    mkdir -p /home/user/deploy_api/src
    cd /home/user/deploy_api

    cat << 'EOF' > Cargo.toml
[package]
name = "deploy_api"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.7.4"
tokio = { version = "1.35.1", features = ["full"] }
serde = { version = "1.0.196", features = ["derive"] }
serde_json = "1.0.113"
EOF

    cat << 'EOF' > src/main.rs
use axum::{routing::post, Json, Router};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct Payload {
    list1: Vec<String>,
    list2: Vec<String>,
}

#[derive(Serialize)]
struct Response {
    merged: Vec<String>,
}

async fn merge_deps(Json(payload): Json<Payload>) -> Json<Response> {
    let mut l1 = payload.list1;
    let l2 = payload.list2;

    // DELIBERATE BORROW CHECKER ERROR
    for item in &l2 {
        l1.push(*item);
    }

    // Sort descending
    l1.sort_by(|a, b| b.cmp(a));
    l1.dedup();

    Json(Response { merged: l1 })
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/merge", post(merge_deps));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:8080").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /usr/local/cargo /usr/local/rustup
