#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git redis-server cargo build-essential curl
    pip3 install pytest

    mkdir -p /app/auth-service
    cd /app/auth-service

    cargo init

    cat << 'EOF' > Cargo.toml
[package]
name = "auth-service"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
base64 = "0.21"
dotenv = "0.15"
redis = "0.23"
EOF

    git init
    git config user.name "Original Developer"
    git config user.email "dev@example.com"

    cat << 'EOF' > src/main.rs
const API_KEY: &str = "zk9_f83jf92_git_leak_99";

fn main() {
    println!("Starting auth service...");
}
EOF
    git add src/main.rs Cargo.toml
    git commit -m "Initial commit"

    cat << 'EOF' > src/main.rs
use axum::{
    routing::post,
    Router,
    Json,
    http::{StatusCode, HeaderMap},
};
use serde_json::Value;
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    dotenv::dotenv().ok();
    let _api_key = std::env::var("SECRET_API_KEY").expect("SECRET_API_KEY must be set");

    let app = Router::new()
        .route("/api/v1/auth", post(auth_handler));

    let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}

async fn auth_handler(headers: HeaderMap, Json(payload): Json<Value>) -> StatusCode {
    let api_key = std::env::var("SECRET_API_KEY").unwrap();
    let auth_header = headers.get("Authorization").and_then(|h| h.to_str().ok()).unwrap_or("");
    if auth_header != format!("Bearer {}", api_key) {
        return StatusCode::UNAUTHORIZED;
    }

    let client_id = payload.get("client_id").unwrap().as_str().unwrap();
    let b64_payload = payload.get("payload").unwrap().as_str().unwrap();

    let decoded = base64::decode(b64_payload).unwrap();
    let _string_payload = String::from_utf8(decoded).unwrap();

    StatusCode::OK
}
EOF
    git add src/main.rs
    git commit -m "Refactor: remove hardcoded secret and implement auth"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
