#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev curl nginx cargo
pip3 install pytest

mkdir -p /home/user/auth_util/clib
mkdir -p /home/user/auth_util/api/src

# 1. Create and compile the C library
cat << 'EOF' > /home/user/auth_util/clib/token.c
#include <string.h>
int validate_token(const char* token) {
    if (!token) return 0;
    if (strncmp(token, "SECURE_", 7) == 0) {
        return 1;
    }
    return 0;
}
EOF

gcc -shared -o /home/user/auth_util/clib/libtoken.so -fPIC /home/user/auth_util/clib/token.c

# 2. Create the buggy Rust API project
cat << 'EOF' > /home/user/auth_util/api/Cargo.toml
[package]
name = "api"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1.0", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
EOF

cat << 'EOF' > /home/user/auth_util/api/src/main.rs
use axum::{
    routing::{post, get},
    Router,
    Json,
    extract::State,
};
use serde::{Deserialize, Serialize};
use std::ffi::CString;
use std::os::raw::c_char;
use std::sync::Arc;
use std::net::SocketAddr;

extern "C" {
    fn validate_token(token: *const c_char) -> i32;
}

#[derive(Deserialize)]
struct TokenReq {
    token: String,
}

#[derive(Serialize)]
struct TokenRes {
    valid: bool,
}

struct AppState {
    prefix: String,
}

async fn validate(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<TokenReq>,
) -> Json<TokenRes> {
    // INTENTIONAL BORROW CHECKER ERROR:
    // Moving out of `state` which is an Arc, and moving `state.prefix`.
    let combined_token = state.prefix + &payload.token; 

    let c_str = CString::new(combined_token).unwrap();
    let result = unsafe { validate_token(c_str.as_ptr()) };

    Json(TokenRes { valid: result == 1 })
}

async fn admin() -> &'static str {
    "Admin panel"
}

#[tokio::main]
async fn main() {
    let state = Arc::new(AppState {
        prefix: "".to_string(), // Empty for simplicity, but forces state usage
    });

    let app = Router::new()
        .route("/validate", post(validate))
        .route("/admin", get(admin))
        .with_state(state);

    let addr = SocketAddr::from(([127, 0, 0, 1], 3000));
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}
EOF

cat << 'EOF' > /home/user/auth_util/api/build.rs
fn main() {
    println!("cargo:rustc-link-search=native=/home/user/auth_util/clib");
    println!("cargo:rustc-link-lib=dylib=token");
}
EOF

# Create user and set permissions
useradd -m -s /bin/bash user || true
chown -R user:user /home/user/auth_util
chmod -R 777 /home/user
