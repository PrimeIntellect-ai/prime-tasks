#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cmake cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data_app/cpp_engine
    mkdir -p /home/user/data_app/rust_server/src

    cat << 'EOF' > /home/user/data_app/cpp_engine/processor.h
#ifndef PROCESSOR_H
#define PROCESSOR_H

#ifdef __cplusplus
extern "C" {
#endif

double process_data(const double* data, int length);

#ifdef __cplusplus
}
#endif

#endif
EOF

    cat << 'EOF' > /home/user/data_app/cpp_engine/processor.cpp
#include "processor.h"

extern "C" {
    double process_data(const double* data, int length) {
        if (length <= 0) return 0.0;

        // BUG: memory leak
        double* temp = new double[length];

        // BUG: <= instead of <
        for(int i = 0; i <= length; i++) {
            temp[i] = data[i] * 2.5;
        }

        double sum = 0;
        for(int i = 0; i < length; i++) {
            sum += temp[i];
        }

        // Missing cleanup
        return sum;
    }
}
EOF

    cat << 'EOF' > /home/user/data_app/cpp_engine/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(Processor CXX)

# BUG: should be a static lib and need -fPIC
add_executable(processor processor.cpp)
EOF

    cat << 'EOF' > /home/user/data_app/rust_server/Cargo.toml
[package]
name = "rust_server"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

[build-dependencies]
cmake = "0.1"
EOF

    cat << 'EOF' > /home/user/data_app/rust_server/build.rs
fn main() {
    let dst = cmake::Config::new("../cpp_engine").build();
    println!("cargo:rustc-link-search=native={}/build", dst.display());
    println!("cargo:rustc-link-lib=static=processor");
}
EOF

    cat << 'EOF' > /home/user/data_app/rust_server/src/main.rs
use axum::{routing::post, Json, Router};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;

extern "C" {
    fn process_data(data: *const f64, length: i32) -> f64;
}

#[derive(Deserialize)]
struct Payload {
    numbers: Vec<f64>,
}

#[derive(Serialize)]
struct ResponsePayload {
    result: f64,
}

async fn process_handler(Json(payload): Json<Payload>) -> Json<ResponsePayload> {
    let result = unsafe {
        process_data(payload.numbers.as_ptr(), payload.numbers.len() as i32)
    };
    Json(ResponsePayload { result })
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/process", post(process_handler));
    let addr = SocketAddr::from(([127, 0, 0, 1], 3000));
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_process_data() {
        let data = vec![1.0, 2.0, 3.0, 4.0];
        let result = unsafe { process_data(data.as_ptr(), data.len() as i32) };
        assert_eq!(result, 25.0); // (1+2+3+4) * 2.5 = 25.0
    }
}
EOF

    cat << 'EOF' > /home/user/data_app/benchmark.sh
#!/bin/bash
if ! curl -s -X POST http://127.0.0.1:3000/process -H "Content-Type: application/json" -d '{"numbers":[1.0, 2.0]}' > /dev/null; then
    echo "Server not responding on port 3000"
    exit 1
fi

echo "Running benchmark..."
for i in {1..100}; do
    curl -s -X POST http://127.0.0.1:3000/process -H "Content-Type: application/json" -d '{"numbers":[1.5, 2.5, 3.5, 4.5]}' > /dev/null
done

echo '{"status": "success", "requests": 100}' > /home/user/benchmark_results.json
EOF
    chmod +x /home/user/data_app/benchmark.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data_app
    chmod -R 777 /home/user
