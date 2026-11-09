#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest websockets

    mkdir -p /home/user/ci_aggregator/src

    cat << 'EOF' > /home/user/mock_ci_server.py
import asyncio
import websockets
import json
import time

async def handler(websocket, path):
    events = [
        {"event": "START", "compute_cost": 1.0, "timestamp_ms": 1000},
        {"event": "BUILD", "compute_cost": 10.0, "timestamp_ms": 1060}, # Valid (60ms diff)
        {"event": "BUILD", "compute_cost": 5.0, "timestamp_ms": 1080},  # Invalid (rate limit - 20ms since last accepted)
        {"event": "TEST", "compute_cost": 20.0, "timestamp_ms": 1150},  # Valid (90ms diff)
        {"event": "DEPLOY", "compute_cost": 15.0, "timestamp_ms": 1210},# Valid (60ms diff)
        {"event": "END", "compute_cost": 2.0, "timestamp_ms": 1270},    # Valid (60ms diff)
        # Sequence 2
        {"event": "START", "compute_cost": 1.0, "timestamp_ms": 1400},  # Valid (130ms diff)
        {"event": "TEST", "compute_cost": 10.0, "timestamp_ms": 1460},  # Invalid (out of order, expecting BUILD)
        {"event": "BUILD", "compute_cost": 12.0, "timestamp_ms": 1520}, # Valid (120ms diff)
        {"event": "TEST", "compute_cost": 8.0, "timestamp_ms": 1550},   # Invalid (rate limit - 30ms diff)
        {"event": "TEST", "compute_cost": 8.0, "timestamp_ms": 1600},   # Valid (80ms diff)
        {"event": "END", "compute_cost": 1.0, "timestamp_ms": 1660},    # Invalid (out of order, expecting DEPLOY)
    ]

    for ev in events:
        await websocket.send(json.dumps(ev))
        await asyncio.sleep(0.01)

start_server = websockets.serve(handler, "127.0.0.1", 8080)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    cat << 'EOF' > /home/user/ci_aggregator/Cargo.toml
[package]
name = "ci_aggregator"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
tokio-tungstenite = "0.19.0"
futures-util = "0.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/ci_aggregator/src/main.rs
use futures_util::StreamExt;
use serde::Deserialize;
use std::fs;
use tokio_tungstenite::connect_async;

#[derive(Deserialize, Debug)]
struct CiEvent {
    event: String,
    compute_cost: f64,
    timestamp_ms: u64,
}

#[tokio::main]
async fn main() {
    let url = "ws://127.0.0.1:8080";
    let (ws_stream, _) = connect_async(url).await.expect("Failed to connect");
    let (_, mut read) = ws_stream.split();

    let mut total_cost = 0.0;

    while let Some(msg) = read.next().await {
        if let Ok(msg) = msg {
            if msg.is_text() {
                if let Ok(event) = serde_json::from_str::<CiEvent>(&msg.into_text().unwrap()) {
                    // TODO: Implement state machine and rate limit
                    total_cost += event.compute_cost;
                }
            }
        }
    }

    fs::write("/home/user/final_cost.txt", format!("{:.2}", total_cost)).unwrap();
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
