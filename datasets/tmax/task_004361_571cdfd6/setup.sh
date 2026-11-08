#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo nginx curl
    pip3 install pytest

    mkdir -p /app/compute-engine/src
    mkdir -p /app/gateway

    cat << 'EOF' > /app/compute-engine/Cargo.toml
[package]
name = "compute-engine"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.7"
tokio = "1.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /app/compute-engine/src/main.rs
use axum::{
    extract::Query,
    routing::get,
    Router,
    Json,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;

#[derive(Deserialize)]
struct ComputeQuery {
    input: String,
}

#[derive(Serialize)]
struct ComputeResponse {
    mean: f32,
    variance: f32,
}

async fn compute(Query(query): Query<ComputeQuery>) -> Json<ComputeResponse> {
    let parts: Vec<&str> = query.input.split(',').collect();
    let mut sum = 0.0_f32;
    let mut sum_sq = 0.0_f32;
    let mut count = 0;

    for part in parts {
        let val: f32 = part.parse().unwrap();
        sum += val;
        sum_sq += val * val;
        count += 1;
    }

    let mean = sum / count as f32;
    let variance = if count < 2 {
        0.0
    } else {
        (sum_sq / count as f32) - (mean * mean)
    };

    Json(ComputeResponse { mean, variance })
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/compute", get(compute));
    let addr = SocketAddr::from(([127, 0, 0, 1], 9000));
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
EOF

    cat << 'EOF' > /app/gateway/nginx.conf
worker_processes 1;
daemon off;
events {
    worker_connections 1024;
}
http {
    server {
        listen 127.0.0.1:8080;
        location /compute {
            # proxy_pass missing
        }
    }
}
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
nginx -c /app/gateway/nginx.conf &
cd /app/compute-engine && cargo run &
wait
EOF

    chmod +x /app/start.sh
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
