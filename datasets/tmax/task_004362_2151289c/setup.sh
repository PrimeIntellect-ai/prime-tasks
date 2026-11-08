#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo nginx redis-server
    pip3 install pytest

    mkdir -p /app/diagnostics /app/rust_api/src /app/rust_api/tests /app/nginx
    echo -e "Some garbage data\nDIAG_PAYLOAD=A7x9F22PqL4mN8vC1bY5zR3wK0jH6tDq\nMore garbage data" > /app/diagnostics/worker_memory.dump

    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            # Intentionally broken port, agent must change 9999 to 3000
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    cat << 'EOF' > /app/rust_api/Cargo.toml
[package]
name = "rust_api"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
redis = { version = "0.23", features = ["tokio-comp"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
lazy_static = "1.4"
EOF

    cat << 'EOF' > /app/rust_api/src/main.rs
use axum::{routing::post, Json, Router};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use std::net::SocketAddr;
use tokio::time::{sleep, Duration};

lazy_static::lazy_static! {
    static ref LOCK_A: Mutex<()> = Mutex::new(());
    static ref LOCK_B: Mutex<()> = Mutex::new(());
}

#[derive(Deserialize)]
struct ProcessRequest {
    payload: String,
}

#[derive(Serialize)]
struct ProcessResponse {
    status: String,
}

async fn process(Json(req): Json<ProcessRequest>) -> Json<ProcessResponse> {
    if req.payload == "A7x9F22PqL4mN8vC1bY5zR3wK0jH6tDq" {
        // Trigger deadlock by locking in wrong order
        let _b = LOCK_B.lock().unwrap();
        sleep(Duration::from_millis(50)).await;
        let _a = LOCK_A.lock().unwrap();
    } else {
        let _a = LOCK_A.lock().unwrap();
        sleep(Duration::from_millis(50)).await;
        let _b = LOCK_B.lock().unwrap();
    }

    // Simulate redis connection
    let client = redis::Client::open("redis://127.0.0.1:6379").unwrap();
    let _con = client.get_tokio_connection().await;

    Json(ProcessResponse {
        status: "processed".to_string(),
    })
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/process", post(process));
    let addr = SocketAddr::from(([127, 0, 0, 1], 3000));
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
