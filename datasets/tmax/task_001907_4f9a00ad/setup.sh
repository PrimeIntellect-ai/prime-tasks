#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake build-essential cargo rustc curl
    pip3 install pytest

    mkdir -p /home/user/workspace/c_math
    mkdir -p /home/user/workspace/api/src
    mkdir -p /home/user/workspace/api/tests

    cat << 'EOF' > /home/user/workspace/c_math/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(cmath C)
add_library(cmath SHARED cmath.c)
EOF

    cat << 'EOF' > /home/user/workspace/c_math/cmath.c
int add(int a, int b) { return a + b; }
int sub(int a, int b) { return a - b; }
EOF

    cat << 'EOF' > /home/user/workspace/api/Cargo.toml
[package]
name = "api"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

[dev-dependencies]
proptest = "1.0"
reqwest = { version = "0.11", features = ["blocking", "json"] }
EOF

    cat << 'EOF' > /home/user/workspace/api/src/main.rs
use axum::{routing::post, Json, Router};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;

#[link(name = "cmath")]
extern "C" {
    fn add(a: i32, b: i32) -> i32;
    fn sub(a: i32, b: i32) -> i32;
}

#[derive(Deserialize)]
struct OpReq { a: i32, b: i32 }

#[derive(Serialize)]
struct OpRes { result: i32 }

async fn handle_add(Json(payload): Json<OpReq>) -> Json<OpRes> {
    let res = unsafe { add(payload.a, payload.b) };
    Json(OpRes { result: res })
}

async fn handle_sub(Json(payload): Json<OpReq>) -> Json<OpRes> {
    let res = unsafe { sub(payload.a, payload.b) };
    Json(OpRes { result: res })
}

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/add", post(handle_add))
        .route("/sub", post(handle_sub));
    let addr = SocketAddr::from(([127, 0, 0, 1], 3000));
    axum::Server::bind(&addr).serve(app.into_make_service()).await.unwrap();
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
