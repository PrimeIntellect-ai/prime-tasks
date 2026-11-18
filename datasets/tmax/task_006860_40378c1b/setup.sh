#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential musl-tools
    pip3 install pytest

    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    export PATH=/usr/local/cargo/bin:$PATH

    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /usr/local/cargo /usr/local/rustup

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_api/src
    cd /home/user/data_api

    cat << 'EOF' > Cargo.toml
[package]
name = "data_api"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

[dev-dependencies]
proptest = "1.2.0"
EOF

    cat << 'EOF' > src/processor.rs
pub fn process_string(input: &str) -> String {
    // Reverses the string characters
    input.chars().rev().collect()
}

pub fn extract_summary(data: String) -> &str {
    // Intentional lifetime/borrowing error
    let summary = data.chars().take(10).collect::<String>();
    &summary
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    // TODO: implement proptest_length_invariant here
}
EOF

    cat << 'EOF' > src/main.rs
use axum::{
    routing::{get, post},
    Router,
    extract::State,
    Json,
};
use std::sync::Arc;
use serde::{Deserialize, Serialize};

mod processor;

struct AppState {
    history: Vec<String>,
}

#[derive(Deserialize)]
struct InputData {
    text: String,
}

#[derive(Serialize)]
struct OutputData {
    processed: String,
    summary: String,
}

// Intentional borrow checker / mutability error with State
async fn handle_post(State(state): State<Arc<AppState>>, Json(payload): Json<InputData>) -> Json<OutputData> {
    let processed = processor::process_string(&payload.text);

    // Fixing compile error here: extract_summary returns a dangling reference, and we shouldn't pass ownership if we need it later.
    // Also state.history requires mutability but AppState is inside Arc without Mutex.
    let summary = processor::extract_summary(payload.text);
    state.history.push(processed.clone());

    Json(OutputData {
        processed,
        summary: summary.to_string(),
    })
}

async fn handle_get(State(state): State<Arc<AppState>>) -> Json<Vec<String>> {
    Json(state.history.clone())
}

#[tokio::main]
async fn main() {
    let state = Arc::new(AppState {
        history: Vec::new(),
    });

    let app = Router::new()
        .route("/process", post(handle_post))
        .route("/history", get(handle_get))
        .with_state(state);

    axum::Server::bind(&"127.0.0.1:3000".parse().unwrap())
        .serve(app.into_make_service())
        .await
        .unwrap();
}
EOF

    chmod -R 777 /home/user
