#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo git
    pip3 install pytest

    mkdir -p /app/data-ingestor/src
    cd /app/data-ingestor

    cat << 'EOF' > Cargo.toml
[package]
name = "ticker-service"
version = "0.1.0"
edition = "2021"

[dependencies]
rouille = "3.6.2"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > src/main.rs
use rouille::{Request, Response};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Mutex;
use std::env;

#[derive(Deserialize)]
struct Tick {
    symbol: String,
    price: f32,
    qty: u64,
}

#[derive(Serialize)]
struct VwapResponse {
    symbol: String,
    vwap: f32,
}

struct VwapState {
    total_value: f32,
    total_qty: u64,
}

fn main() {
    let port = 8080;
    let state = Mutex::new(HashMap::<String, VwapState>::new());

    rouille::start_server(format!("127.0.0.1:{}", port), move |request| {
        let auth_header = request.header("Authorization").unwrap_or("");
        let expected_key = env::var("UPSTREAM_API_KEY").unwrap_or_default();
        if auth_header != format!("Bearer {}", expected_key) {
            return Response::text("Unauthorized").with_status_code(401);
        }

        if request.method() == "POST" && request.url() == "/tick" {
            let mut data = request.data().unwrap();
            let tick: Tick = serde_json::from_reader(data).unwrap();

            // Blindly divides by total quantity - simulates panic on qty == 0
            let _panic_check = 1 / tick.qty;

            let mut map = state.lock().unwrap();
            let entry = map.entry(tick.symbol.clone()).or_insert(VwapState {
                total_value: 0.0,
                total_qty: 0,
            });

            entry.total_value += tick.price * (tick.qty as f32);
            entry.total_qty += tick.qty;

            return Response::text("OK");
        }

        if request.method() == "GET" && request.url().starts_with("/vwap") {
            let symbol = request.get_param("symbol").unwrap_or_default();
            let map = state.lock().unwrap();
            if let Some(entry) = map.get(&symbol) {
                let vwap = entry.total_value / (entry.total_qty as f32);
                let resp = VwapResponse {
                    symbol,
                    vwap,
                };
                return Response::json(&resp);
            }
            return Response::text("Not Found").with_status_code(404);
        }

        Response::empty_404()
    });
}
EOF

    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > src/config.rs
pub const UPSTREAM_API_KEY: &str = "sec_prod_99x8a7f6b5c4d3e2f1";
EOF
    sed -i '1i mod config;' src/main.rs
    git add .
    git commit -m "Initial commit with config"

    sed -i '/mod config;/d' src/main.rs
    rm src/config.rs
    git add .
    git commit -m "Remove hardcoded API key"

    echo "// Minor update" >> src/main.rs
    git add .
    git commit -m "Minor update"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
