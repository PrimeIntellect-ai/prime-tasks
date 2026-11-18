#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl openssl cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/auth-server/src

    cat << 'EOF' > /home/user/auth-server/Cargo.toml
[package]
name = "auth-server"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
axum-server = { version = "0.5", features = ["tls-rustls"] }
EOF

    cat << 'EOF' > /home/user/auth-server/src/main.rs
use axum::{
    extract::Query,
    http::header,
    response::{IntoResponse, Redirect, Response},
    routing::get,
    Router,
};
use axum_server::tls_rustls::RustlsConfig;
use serde::Deserialize;
use std::net::SocketAddr;

#[derive(Deserialize)]
struct LoginQuery {
    next: Option<String>,
}

async fn login_handler(Query(query): Query<LoginQuery>) -> Response {
    let redirect_url = query.next.unwrap_or_else(|| "/dashboard".to_string());

    // VULNERABLE: Open Redirect
    Redirect::temporary(&redirect_url).into_response()
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/login", get(login_handler));

    let config = RustlsConfig::from_pem_file(
        "/home/user/certs/server.crt",
        "/home/user/certs/server.key",
    )
    .await
    .expect("Failed to load TLS certificates");

    let addr = SocketAddr::from(([127, 0, 0, 1], 8443));
    println!("listening on https://{}", addr);
    axum_server::bind_rustls(addr, config)
        .serve(app.into_make_service())
        .await
        .unwrap();
}
EOF

    chown -R user:user /home/user/auth-server
    chmod -R 777 /home/user
