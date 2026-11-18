#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential nginx cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/rust_api/src

    cat << 'EOF' > /home/user/app/rust_api/Cargo.toml
[package]
name = "rust_api"
version = "0.1.0"
edition = "2021"

[dependencies]
actix-web = "4.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/app/rust_api/src/main.rs
use actix_web::{web, App, HttpServer, HttpResponse, Responder};
use serde::{Deserialize, Serialize};
mod math;

#[derive(Deserialize)]
struct PowRequest {
    matrix: [[i64; 2]; 2],
    n: u32,
}

#[derive(Serialize)]
struct PowResponse {
    result: [[i64; 2]; 2],
}

async fn matrix_pow_handler(req: web::Json<PowRequest>) -> impl Responder {
    // Intentional error: math::power is incomplete and incorrectly called
    let res = math::power(req.matrix, req.n);
    HttpResponse::Ok().json(PowResponse { result: res })
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new().route("/api/matrix_pow", web::post().to(matrix_pow_handler))
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}
EOF

    cat << 'EOF' > /home/user/app/rust_api/src/math.rs
pub fn multiply(a: [[i64; 2]; 2], b: [[i64; 2]; 2]) -> [[i64; 2]; 2] {
    [
        [
            a[0][0] * b[0][0] + a[0][1] * b[1][0],
            a[0][0] * b[0][1] + a[0][1] * b[1][1],
        ],
        [
            a[1][0] * b[0][0] + a[1][1] * b[1][0],
            a[1][0] * b[0][1] + a[1][1] * b[1][1],
        ],
    ]
}

pub fn power(mut base: [[i64; 2]; 2], mut n: u32) -> [[i64; 2]; 2] {
    // Intentional error: uninitialized identity matrix, missing implementation
    let mut res = [[1, 0], [0, 1]];
    // missing binary exponentiation logic
    res
}
EOF

    cat << 'EOF' > /home/user/app/nginx.conf
events {}
http {
    server {
        listen 9000;
        # Agent must configure reverse proxy for /api/
    }
}
EOF

    chmod -R 777 /home/user
