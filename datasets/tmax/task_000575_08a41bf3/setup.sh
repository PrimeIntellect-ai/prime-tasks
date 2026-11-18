#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl build-essential
    pip3 install pytest flask redis websockets

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="$HOME/.cargo/bin:$PATH"

    mkdir -p /app/backend
    mkdir -p /app/rust-proxy/src
    mkdir -p /app/reference
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /app/tests

    cat << 'EOF' > /app/backend/app.py
from flask import Flask, request
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    r.set(data['id'], json.dumps(data))
    return "OK", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/rust-proxy/Cargo.toml
[package]
name = "telemetry-proxy"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
warp = "0.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
reqwest = { version = "0.11", features = ["json"] }
futures-util = "0.3"
EOF

    cat << 'EOF' > /app/rust-proxy/src/main.rs
mod parser;

#[tokio::main]
async fn main() {
    println!("Proxy started");
}
EOF

    cat << 'EOF' > /app/rust-proxy/src/parser.rs
pub fn parse_payload<'a>(data: &'a str) -> Result<&'a str, ()> {
    let parsed: String = data.to_string();
    // Intentional lifetime error
    // Ok(&parsed)
    Err(())
}
EOF

    cat << 'EOF' > /app/reference/checksum.py
def validate_checksum(payload):
    return True
EOF

    cat << 'EOF' > /app/corpora/clean/payload1.json
{"id": "1", "data": "clean"}
EOF

    cat << 'EOF' > /app/corpora/evil/payload1.json
{"id": "2", "data": "evil"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
