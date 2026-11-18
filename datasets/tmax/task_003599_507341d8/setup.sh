#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cargo
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_oracle.cpp
#include <iostream>
#include <string>
#include <iomanip>

int main() {
    std::string s;
    std::getline(std::cin, s);
    double sum = 0.0;
    double c = 0.0;
    std::string token;
    for (char ch : s) {
        if (std::isdigit(ch) || ch == '-' || ch == '.' || ch == 'e' || ch == 'E' || ch == '+') {
            token += ch;
        } else {
            if (!token.empty()) {
                try {
                    double y = std::stod(token) - c;
                    double t = sum + y;
                    c = (t - sum) - y;
                    sum = t;
                } catch (...) {}
                token.clear();
            }
        }
    }
    if (!token.empty()) {
        try {
            double y = std::stod(token) - c;
            double t = sum + y;
            c = (t - sum) - y;
            sum = t;
        } catch (...) {}
    }
    std::cout << "{\"result\": " << std::setprecision(15) << sum << "}\n";
    return 0;
}
EOF
    g++ -O3 -static /app/legacy_oracle.cpp -o /app/legacy_oracle
    strip /app/legacy_oracle
    rm /app/legacy_oracle.cpp

    mkdir -p /home/user/aggregator/src
    cat << 'EOF' > /home/user/aggregator/Cargo.toml
[package]
name = "aggregator"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/aggregator/src/main.rs
use axum::{
    routing::{get, post},
    Router, Json,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use tokio::sync::mpsc;
use std::time::Duration;

#[derive(Deserialize)]
struct Payload {
    values: Vec<f32>,
}

#[derive(Serialize)]
struct Response {
    result: f32,
}

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/health", get(|| async { "OK" }))
        .route("/aggregate", post(aggregate));

    let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}

async fn aggregate(Json(payload): Json<Payload>) -> Json<Response> {
    // Bug 1: Naive f32 sum
    let sum: f32 = payload.values.iter().sum();

    // Bug 2: Task leak. Simulate background work that doesn't cancel when client drops.
    let (tx, mut rx) = mpsc::unbounded_channel();
    tokio::spawn(async move {
        // Leaks if client disconnects before this finishes
        tokio::time::sleep(Duration::from_secs(10)).await;
        let _ = tx.send(sum);
    });

    let res = rx.recv().await.unwrap_or(sum);
    Json(Response { result: res })
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/aggregator
    chmod -R 777 /home/user
