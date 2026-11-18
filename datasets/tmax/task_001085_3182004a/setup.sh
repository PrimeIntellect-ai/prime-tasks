#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc curl build-essential
    pip3 install pytest

    mkdir -p /home/user/math_ws_server/src
    cd /home/user/math_ws_server

    cat << 'EOF' > Cargo.toml
[package]
name = "math_ws_server"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.0", features = ["full"] }
warp = "0.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
futures-util = "0.3"
EOF

    cat << 'EOF' > src/main.rs
mod math;
mod server;

#[tokio::main]
async fn main() {
    server::run_server().await;
}
EOF

    cat << 'EOF' > src/math.rs
pub fn solve_diophantine(r: i32) -> Vec<(i32, i32)> {
    // TODO: Implement constraint satisfaction numerical algorithm
    // Find all x >= 0, y >= 0 where x^2 + y^2 = r
    unimplemented!()
}

pub fn format_and_sort_solutions(solutions: &Vec<(i32, i32)>) -> String {
    // BROKEN: Lifetime and type issues
    let mut cloned = solutions.clone();
    cloned.sort_by(|a, b| a.1.cmp(b.0)); // Buggy sort

    let mut result = Vec::new();
    for s in cloned {
        result.push(vec![s.0, s.1]);
    }

    serde_json::to_string(&result).unwrap()
}
EOF

    cat << 'EOF' > src/server.rs
use warp::Filter;
use futures_util::{StreamExt, SinkExt};
use serde::Deserialize;

#[derive(Deserialize)]
struct SolveRequest {
    r: i32,
}

pub async fn run_server() {
    let ws_route = warp::path("solve")
        .and(warp::ws())
        .map(|ws: warp::ws::Ws| {
            ws.on_upgrade(handle_socket)
        });

    warp::serve(ws_route).run(([127, 0, 0, 1], 8080)).await;
}

async fn handle_socket(ws: warp::ws::WebSocket) {
    let (mut tx, mut rx) = ws.split();

    while let Some(result) = rx.next().await {
        // BROKEN: Missing actual parsing and logic to call math::solve_diophantine
        // let msg = result.unwrap();
        // let req: SolveRequest = serde_json::from_str(msg.to_str().unwrap()).unwrap();
        // let solutions = crate::math::solve_diophantine(req.r);
        // let response_str = crate::math::format_and_sort_solutions(&solutions);
        // tx.send(warp::ws::Message::text(response_str)).await.unwrap();
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
