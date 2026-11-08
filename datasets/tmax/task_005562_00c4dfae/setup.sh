#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo binutils
    pip3 install pytest fastapi httpx maturin

    mkdir -p /home/user/project/src
    mkdir -p /home/user/ci_artifacts

    cat << 'EOF' > /home/user/project/Cargo.toml
[package]
name = "rate_limiter"
version = "0.1.0"
edition = "2021"

[lib]
name = "rate_limiter"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    cat << 'EOF' > /home/user/project/pyproject.toml
[build-system]
requires = ["maturin>=1.0,<2.0"]
build-backend = "maturin"

[project]
name = "rate_limiter"
version = "0.1.0"
requires-python = ">=3.8"
EOF

    cat << 'EOF' > /home/user/project/src/lib.rs
use pyo3::prelude::*;

#[pyfunction]
fn is_rate_limited(ip: String) -> bool {
    let ip_ref = &ip;
    let limited = check_ip(ip); // Moves `ip` here
    if limited {
        // ERROR: borrow used here after move
        println!("Rate limited: {}", ip_ref); 
    }
    limited
}

fn check_ip(ip: String) -> bool {
    ip == "127.0.0.1"
}

#[pymodule]
fn rate_limiter(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(is_rate_limited, m)?)?;
    Ok(())
}
EOF

    cat << 'EOF' > /home/user/project/main.py
import os
import sys
from fastapi import FastAPI, Request, HTTPException

if "pytest" in sys.modules and os.environ.get("TEST_MODE") != "1":
    raise RuntimeError("TEST_MODE environment variable must be set before importing main in tests!")

try:
    from rate_limiter import is_rate_limited
except ImportError:
    # fallback for local editing
    def is_rate_limited(ip): return False

app = FastAPI()

@app.get("/")
def read_root(request: Request):
    client_ip = request.client.host if request.client else "127.0.0.1"
    if is_rate_limited(client_ip):
        raise HTTPException(status_code=429, detail="Rate Limited")
    return {"status": "ok"}
EOF

    cat << 'EOF' > /home/user/project/test_main.py
from main import app
import os
os.environ["TEST_MODE"] = "1"
from fastapi.testclient import TestClient

def test_read_root():
    client = TestClient(app)
    response = client.get("/")
    # Note: 127.0.0.1 is rate limited in the Rust extension, so it should return 429
    assert response.status_code == 429
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project /home/user/ci_artifacts
    chmod -R 777 /home/user
