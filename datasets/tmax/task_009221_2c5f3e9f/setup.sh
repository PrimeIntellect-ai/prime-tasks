#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc sqlite3 nginx
pip3 install pytest

mkdir -p /home/user/app/src
cd /home/user/app

cat << 'EOF' > Cargo.toml
[package]
name = "secure-api"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

cat << 'EOF' > src/main.rs
use axum::{routing::post, Router};
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/api/register", post(api::register_user));

    let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}
EOF

cat << 'EOF' > src/models.rs
use serde::Deserialize;

#[derive(Deserialize)]
pub struct RegisterRequest {
    pub username: String,
    pub password: String,
}

pub struct RegisterResponse {
    pub status: String,
    pub message: String,
}
EOF

cat << 'EOF' > src/api.rs
use axum::{Json, http::StatusCode};
use crate::models::{RegisterRequest, RegisterResponse};

pub async fn register_user(
    Json(payload): Json<RegisterRequest>,
) -> (StatusCode, Json<RegisterResponse>) {
    if payload.password.len() < 8 {
        return (
            StatusCode::BAD_REQUEST,
            Json(RegisterResponse {
                status: "error".to_string(),
                message: "Password too short".to_string(),
            }),
        );
    }

    (
        StatusCode::OK,
        Json(RegisterResponse {
            status: "success".to_string(),
            message: "User registered".to_string(),
        }),
    )
}
EOF

cat << 'EOF' > schema.sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL
);
EOF

cat << 'EOF' > /home/user/nginx.conf
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;

        location /api/ {
            proxy_pass http://127.0.0.1:8080;
        }
    }
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
