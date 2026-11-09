#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server rustc cargo
    pip3 install pytest fastapi uvicorn websockets redis aiohttp numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/rust_engine/src
    mkdir -p /home/user/app/python_gateway

    cat << 'EOF' > /home/user/app/reference_math.py
def calculate_determinant(matrix):
    if len(matrix) == 1:
        return matrix[0][0]
    if len(matrix) == 2:
        return matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0]
    det = 0
    for c in range(len(matrix)):
        sub_matrix = [row[:c] + row[c+1:] for row in matrix[1:]]
        det += ((-1) ** c) * matrix[0][c] * calculate_determinant(sub_matrix)
    return det
EOF

    cat << 'EOF' > /home/user/app/rust_engine/Cargo.toml
[package]
name = "math_engine"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
warp = "0.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
futures-util = "0.3"
EOF

    cat << 'EOF' > /home/user/app/rust_engine/src/main.rs
use warp::Filter;
use futures_util::{StreamExt, SinkExt};
use serde::{Deserialize, Serialize};

mod math;

#[derive(Deserialize)]
struct MatrixPayload {
    matrix: Vec<Vec<f64>>,
}

#[derive(Serialize)]
struct ResultPayload {
    determinant: f64,
}

#[tokio::main]
async fn main() {
    let ws_route = warp::path("math")
        .and(warp::ws())
        .map(|ws: warp::ws::Ws| {
            ws.on_upgrade(|mut websocket| async move {
                if let Some(result) = websocket.next().await {
                    if let Ok(msg) = result {
                        if let Ok(text) = msg.to_str() {
                            if let Ok(payload) = serde_json::from_str::<MatrixPayload>(text) {
                                let det = math::calculate_determinant(&payload.matrix);
                                let res = ResultPayload { determinant: det };
                                let res_text = serde_json::to_string(&res).unwrap();
                                let _ = websocket.send(warp::ws::Message::text(res_text)).await;
                            }
                        }
                    }
                }
            })
        });

    warp::serve(ws_route).run(([127, 0, 0, 1], 8001)).await;
}
EOF

    cat << 'EOF' > /home/user/app/rust_engine/src/math.rs
// Implement calculate_determinant here
EOF

    cat << 'EOF' > /home/user/app/python_gateway/main.py
from fastapi import FastAPI

app = FastAPI()

@app.get("/matrix/{id}")
def broken_route(id: int):
    return {"status": "broken"}
EOF

    cat << 'EOF' > /home/user/verifier_benchmark.py
import asyncio
import aiohttp
import numpy as np
import time

async def fetch(session, url, payload):
    start = time.time()
    async with session.post(url, json=payload) as response:
        await response.json()
    return (time.time() - start) * 1000

async def main():
    url = "http://localhost:8000/api/v1/matrix/determinant"
    payload = {"matrix": [[1, 2], [3, 4]]}
    async with aiohttp.ClientSession() as session:
        tasks = [fetch(session, url, payload) for _ in range(1000)]
        latencies = await asyncio.gather(*tasks)
        p95 = np.percentile(latencies, 95)
        print(p95)

if __name__ == "__main__":
    asyncio.run(main())
EOF

    chmod -R 777 /home/user
