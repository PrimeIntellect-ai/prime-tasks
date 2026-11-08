#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo nginx
    pip3 install pytest websockets

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ws-ingest/src

    cat << 'EOF' > /home/user/ws-ingest/Cargo.toml
[package]
name = "ws-ingest"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
tokio-tungstenite = "0.20"
futures-util = "0.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
crc32fast = "1.3"
EOF

    cat << 'EOF' > /home/user/ws-ingest/src/main.rs
mod parser;
mod checksum;

use std::net::SocketAddr;
use tokio::net::TcpListener;
use tokio_tungstenite::accept_async;
use futures_util::{StreamExt, SinkExt};

#[tokio::main]
async fn main() {
    let addr = "127.0.0.1:9090".parse::<SocketAddr>().unwrap();
    let listener = TcpListener::bind(&addr).await.expect("Failed to bind");

    while let Ok((stream, _)) = listener.accept().await {
        tokio::spawn(async move {
            if let Ok(mut ws_stream) = accept_async(stream).await {
                if let Some(Ok(msg)) = ws_stream.next() {
                    if let Ok(text) = msg.to_text() {
                        let result = parser::process_message(text);
                        let _ = ws_stream.send(tokio_tungstenite::tungstenite::Message::Text(result)).await;
                    }
                }
            }
        });
    }
}
EOF

    cat << 'EOF' > /home/user/ws-ingest/src/parser.rs
use serde::{Deserialize, Serialize};
use crate::checksum::verify_checksum;

#[derive(Deserialize)]
pub struct Payload {
    pub data: String,
    pub checksum: String,
}

pub fn process_message(input: &str) -> String {
    match serde_json::from_str::<Payload>(input) {
        Ok(payload) => {
            if verify_checksum(&payload.data, payload.checksum) {
                "SUCCESS: Checksum verified".to_string()
            } else {
                "ERROR: Invalid checksum".to_string()
            }
        }
        Err(_) => "ERROR: Invalid JSON".to_string(),
    }
}
EOF

    cat << 'EOF' > /home/user/ws-ingest/src/checksum.rs
use crc32fast::Hasher;

pub fn verify_checksum(data: &str, expected: u32) -> bool {
    let mut hasher = Hasher::new();
    hasher.update(data);
    hasher.finalize() == expected
}
EOF

    cat << 'EOF' > /home/user/nginx_base.conf
worker_processes 1;
pid /home/user/nginx.pid;
error_log /home/user/error.log;

events {
    worker_connections 1024;
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
