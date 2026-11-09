#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl expect build-essential supervisor
    pip3 install pytest requests

    # Install Rust minimally
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    export PATH="$HOME/.cargo/bin:$PATH"

    mkdir -p /app/rust_processor/src
    mkdir -p /app/data
    touch /app/data/metrics.db

    # Create Rust project
    cd /app/rust_processor
    cat << 'EOF' > Cargo.toml
[package]
name = "metrics_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
actix-web = "4.3.1"
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > src/main.rs
use actix_web::{web, App, HttpServer, HttpResponse, Responder};
use serde::Deserialize;

#[derive(Deserialize)]
struct Batch {
    count: usize,
}

async fn process_batch(info: web::Json<Batch>) -> impl Responder {
    let mut vec = Vec::new();
    for i in 0..info.count {
        vec.insert(0, i);
    }
    HttpResponse::Ok().body(format!("Processed {}", vec.len()))
}

async fn index() -> impl Responder {
    HttpResponse::Ok().body("OK")
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .route("/", web::get().to(index))
            .route("/process_batch", web::post().to(process_batch))
    })
    .bind(("127.0.0.1", 8082))?
    .run()
    .await
}
EOF

    # Build the Rust project
    cargo build --release

    # Create Python scripts
    cat << 'EOF' > /app/deploy_manager.py
import sys
import time

def main():
    if "--binary" not in sys.argv:
        print("Usage: deploy_manager.py --binary <path>")
        sys.exit(1)

    ans = input("Deploy to stage 1 (10%)? [y/N]: ")
    if ans.lower() != 'y': sys.exit(1)

    ans = input("Deploy to stage 2 (50%)? [y/N]: ")
    if ans.lower() != 'y': sys.exit(1)

    ans = input("Deploy to stage 3 (100%)? [y/N]: ")
    if ans.lower() != 'y': sys.exit(1)

    ans = input("Commit rollout? [y/N]: ")
    if ans.lower() != 'y': sys.exit(1)

    print("Deployment successful.")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /app/verify_speed.py
import time, requests, sys
start = time.time()
try:
    r = requests.post("http://localhost:8082/process_batch", json={"count": 50000})
    latency = time.time() - start
    assert r.status_code == 200
    assert latency <= 1.0, f"Latency {latency}s exceeds 1.0s threshold"
    print(f"LATENCY_METRIC: {latency}")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
EOF

    cat << 'EOF' > /app/emitter.py
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")
HTTPServer(('127.0.0.1', 8081), Handler).serve_forever()
EOF

    # Create a supervisord config to run the services for tests
    cat << 'EOF' > /etc/supervisor/conf.d/services.conf
[supervisord]
nodaemon=true

[program:emitter]
command=python3 /app/emitter.py
autostart=true
autorestart=true

[program:processor]
command=/app/rust_processor/target/release/metrics_processor
autostart=true
autorestart=true
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
