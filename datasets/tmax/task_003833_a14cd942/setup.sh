#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv redis-server cargo rustc libssl-dev pkg-config
    pip3 install pytest flask redis requests maturin

    mkdir -p /app/backend
    cat << 'EOF' > /app/backend/app.py
import os
import json
from flask import Flask, jsonify
import redis

app = Flask(__name__)
redis_url = os.environ.get("REDIS_URL")
if not redis_url:
    raise ValueError("REDIS_URL not set")

r = redis.Redis.from_url(redis_url)

@app.route('/api/artifact/<id>')
def get_artifact(id):
    return jsonify({"id": id, "name": f"Artifact {id}", "size": 1024, "status": "ok"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    mkdir -p /home/user/fast_artifact/src
    cat << 'EOF' > /home/user/fast_artifact/pyproject.toml
[project]
name = "fast_artifact"
version = "0.1.0"
requires-python = ">=3.7"
EOF

    cat << 'EOF' > /home/user/fast_artifact/Cargo.toml
[package]
name = "fast_artifact"
version = "0.1.0"
edition = "2021"

[lib]
name = "fast_artifact"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19", features = ["extension-module"] }
reqwest = { version = "0.11", features = ["blocking", "json"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/fast_artifact/src/lib.rs
use pyo3::prelude::*;
use reqwest::blocking::get;
use serde::Deserialize;

#[derive(Deserialize)]
struct Artifact {
    id: String,
    name: String,
    size: u32,
    status: String,
}

fn format_url(id: &str) -> &str {
    let url = format!("http://localhost:8080/api/artifact/{}", id);
    &url
}

#[pyfunction]
fn fetch_artifact(id: &str) -> PyResult<String> {
    let url = format_url(id);
    let response = get(url).unwrap().text().unwrap();
    Ok(response)
}

#[pymodule]
fn fast_artifact(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(fetch_artifact, m)?)?;
    Ok(())
}
EOF

    cat << 'EOF' > /home/user/benchmark.py
import time
import json
import sys

try:
    import fast_artifact
except ImportError:
    print("fast_artifact not installed")
    sys.exit(1)

start = time.time()
for i in range(5000):
    fast_artifact.fetch_artifact(str(i))
end = time.time()

with open("/home/user/metrics.json", "w") as f:
    json.dump({"total_time_seconds": end - start}, f)
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
