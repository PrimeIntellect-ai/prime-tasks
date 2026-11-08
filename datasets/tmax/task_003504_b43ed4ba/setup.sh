#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc ffmpeg curl
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=12:size=640x480:rate=25 -c:v libx264 -y /app/datacenter_feed.mp4

    mkdir -p /home/user/monitor-service/src
    cat << 'EOF' > /home/user/monitor-service/Cargo.toml
[package]
name = "monitor-service"
version = "0.1.0"
edition = "2021"

[dependencies]
warp = "0.3"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/monitor-service/src/main.rs
use warp::Filter;
use std::sync::Arc;
use serde::Serialize;

#[derive(Serialize)]
struct Metrics {
    uptime_status: String,
    processed_frames: u32,
    anomalies_detected: u32,
}

#[tokio::main]
async fn main() {
    let metrics = warp::path("metrics").map(|| {
        warp::reply::json(&Metrics {
            uptime_status: "healthy".to_string(),
            processed_frames: 0,
            anomalies_detected: 0,
        })
    });

    warp::serve(metrics).run(([127, 0, 0, 1], 9090)).await;
}
EOF

    mkdir -p /home/user/dumps
    echo "dummy core dump" > /home/user/dumps/core.monitor-service

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
