#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl bubblewrap openssh-client cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/src
    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/app/Cargo.toml
[package]
name = "web_app"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > /home/user/app/src/main.rs
use axum::{extract::Query, response::Redirect, routing::get, Router};
use serde::Deserialize;

#[derive(Deserialize)]
struct LoginQuery {
    next: Option<String>,
}

async fn login(Query(query): Query<LoginQuery>) -> Redirect {
    let next_url = query.next.unwrap_or_else(|| "/dashboard".to_string());
    // VULNERABLE: Open Redirect
    Redirect::to(&next_url)
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/login", get(login));
    axum::Server::bind(&"127.0.0.1:8080".parse().unwrap())
        .serve(app.into_make_service())
        .await
        .unwrap();
}
EOF

    chmod -R 777 /home/user
    chmod 700 /home/user/.ssh
