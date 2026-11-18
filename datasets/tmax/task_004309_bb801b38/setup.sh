#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl build-essential
    pip3 install pytest flask redis

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /home/user/pipeline/rust_worker/src
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Create Python API skeleton
    cat << 'EOF' > /home/user/pipeline/api.py
from flask import Flask, request
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/process', methods=['POST'])
def process():
    data = request.json
    r.lpush('graph_queue', json.dumps(data))
    return 'OK'

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create Rust worker skeleton
    cat << 'EOF' > /home/user/pipeline/rust_worker/Cargo.toml
[package]
name = "rust_worker"
version = "0.1.0"
edition = "2021"

[dependencies]
rayon = "1.5"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
redis = "0.22"
EOF

    cat << 'EOF' > /home/user/pipeline/rust_worker/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    # Create clean corpus
    for i in 1 2 3 4 5; do
        cat <<EOF > /home/user/corpus/clean/clean_${i}.json
{
  "id": "clean_${i}",
  "nodes": [1, 2, 3],
  "edges": [[1, 2], [2, 3], [1, 3]]
}
EOF
    done

    # Create evil corpus
    for i in 1 2 3 4 5; do
        cat <<EOF > /home/user/corpus/evil/evil_${i}.json
{
  "id": "evil_${i}",
  "nodes": [0, 1, 2, 3, 4, 5],
  "edges": [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5]]
}
EOF
    done

    useradd -m -s /bin/bash user || true

    # Make rust available for the user
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup
    chown -R user:user /home/user/.cargo /home/user/.rustup

    chmod -R 777 /home/user
