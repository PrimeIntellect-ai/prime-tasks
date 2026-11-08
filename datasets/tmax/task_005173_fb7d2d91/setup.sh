#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y archivemount fuse curl cargo openssl zip

    # Create user
    useradd -m -s /bin/bash user || true

    # Create dummy certs and zip them
    mkdir -p /tmp/certs
    openssl req -x509 -newkey rsa:4096 -keyout /tmp/certs/key.pem -out /tmp/certs/cert.pem -sha256 -days 365 -nodes -subj "/CN=localhost"
    cd /tmp && zip -r /home/user/certs.zip certs/*
    rm -rf /tmp/certs

    # Create paths
    mkdir -p /home/user/app/certs
    mkdir -p /home/user/app/health-server/src
    mkdir -p /home/user/.config/systemd/user

    # Create Rust project Cargo.toml
    cat << 'EOF' > /home/user/app/health-server/Cargo.toml
[package]
name = "health-server"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
axum-server = { version = "0.5", features = ["tls-rustls"] }
EOF

    # Create broken main.rs
    cat << 'EOF' > /home/user/app/health-server/src/main.rs
use axum::{routing::get, Router};
use axum_server::tls_rustls::RustlsConfig;
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    let config = RustlsConfig::from_pem_file(
        "/home/user/app/certs/cert.pem",
        "/home/user/app/certs/key.pem",
    )
    .await
    .unwrap();

    let app = Router::new().route("/health", get(health_handler));

    // BUG: Binding to privileged port
    let addr = SocketAddr::from(([0, 0, 0, 0], 443));
    axum_server::bind_rustls(addr, config)
        .serve(app.into_make_service())
        .await
        .unwrap();
}

// BUG: Returns 500
async fn health_handler() -> &'static str {
    todo!("Not implemented")
}
EOF

    # Create systemd unit
    cat << 'EOF' > /home/user/.config/systemd/user/health-server.service
[Unit]
Description=Health Server

[Service]
Type=simple
WorkingDirectory=/home/user/app/health-server
ExecStart=/home/user/app/health-server/target/release/health-server
EOF

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
