#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl nginx cargo rustc
    pip3 install pytest

    # Create directory structure
    mkdir -p /app/artifact_manager/data/binaries
    mkdir -p /app/artifact_manager/nginx
    mkdir -p /app/artifact_manager/rust_backend/src

    # Create the legacy manifest in UTF-8, then convert to ISO-8859-1
    cat << 'EOF' > /tmp/manifest.utf8
test_artifact.bin|a1b2c3|1048576
façade.bin|d4e5f6|123
EOF
    iconv -f UTF-8 -t ISO-8859-1 /tmp/manifest.utf8 > /app/artifact_manager/data/manifest.legacy
    rm /tmp/manifest.utf8

    # Create a dummy binary file
    dd if=/dev/urandom of=/app/artifact_manager/data/binaries/test_artifact.bin bs=1M count=1

    # Create Cargo.toml
    cat << 'EOF' > /app/artifact_manager/rust_backend/Cargo.toml
[package]
name = "artifact_backend"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
memmap2 = "0.7"
EOF

    # Create skeleton main.rs
    cat << 'EOF' > /app/artifact_manager/rust_backend/src/main.rs
use axum::{routing::get, Router};
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/artifact/:name", get(get_artifact));

    let addr = SocketAddr::from(([127, 0, 0, 1], 9000));
    println!("Listening on {}", addr);
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}

async fn get_artifact() -> &'static str {
    // TODO: implement memory-mapped file reading
    "Stub"
}
EOF

    # Create skeleton nginx.conf
    cat << 'EOF' > /app/artifact_manager/nginx/nginx.conf
events {
    worker_connections 1024;
}

http {
    server {
        listen 8000;

        # TODO: Route /api/* to the Rust backend at 127.0.0.1:9000
    }
}
EOF

    # Set permissions
    chmod -R 777 /app

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
