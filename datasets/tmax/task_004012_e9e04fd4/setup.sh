#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        curl \
        build-essential

    pip3 install pytest maturin websockets

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/math_ws_project/rust_engine/src
    cd /home/user/math_ws_project

    cat << 'EOF' > pure_python.py
import math

def compute_trajectory(alpha, beta, iterations):
    x, y = 0.1, 0.1
    res = []
    for _ in range(iterations):
        nx = math.sin(alpha * y) - math.cos(beta * x)
        ny = math.sin(beta * x) - math.cos(alpha * y)
        x, y = nx, ny
        res.append((x, y))
    return res
EOF

    cat << 'EOF' > rust_engine/src/lib.rs
use pyo3::prelude::*;

#[pyfunction]
fn compute_trajectory(alpha: f64, beta: f64, iterations: usize) -> PyResult<Vec<(f64, f64)>> {
    let mut x = 0.1;
    let mut y = 0.1;
    let mut res = Vec::with_capacity(iterations);

    for _ in 0..iterations {
        let nx = (alpha * y).sin() - (beta * x).cos();
        let ny = (beta * x).sin() - (alpha * y).cos();

        // BORROW CHECKER ERROR: Trying to push a reference to local variables that drop
        // res.push((&x, &y)); // Buggy line
        x = nx;
        y = ny;
        res.push((x, y)); // (Agent must fix to this or similar)
    }

    // Bug: Returning a reference to res instead of moving it
    // Ok(&res)
    Ok(res) // Agent must fix
}

#[pymodule]
fn rust_engine(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(compute_trajectory, m)?)?;
    Ok(())
}
EOF

    cat << 'EOF' > rust_engine/Cargo.toml
[package]
name = "rust_engine"
version = "0.1.0"
edition = "2021"

[lib]
# BUG: missing crate-type = ["cdylib"]
name = "rust_engine"

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    cat << 'EOF' > pyproject.toml
[build-system]
requires = ["maturin>=1.0,<2.0"]
build-backend = "maturin"

[project]
name = "math_ws_project"
version = "0.1.0"
EOF

    cat << 'EOF' > server.py
import asyncio
import websockets
import json
from rust_engine import compute_trajectory

async def handler(websocket, path):
    # hardcoded dummy params for testing server
    traj = compute_trajectory(1.0, 1.0, 100)

    # BUG: json.dumps can't serialize a custom Rust object if it wasn't converted properly,
    # or the bug could simply be that they do json.dumps(traj) but send bytes instead of str, 
    # or they try to serialize a set. Let's do a simple bug:

    # Buggy line:
    # message = "DATA:" + traj

    # Corrected:
    message = json.dumps(traj)
    await websocket.send(message)

start_server = websockets.serve(handler, "localhost", 8765)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    mkdir -p /app
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
    -draw "text 20,50 'ALPHA=1.75'" \
    -draw "text 20,100 'BETA=0.95'" \
    -draw "text 20,150 'ITERATIONS=1000000'" \
    /app/sys_config.png

    chmod -R 777 /home/user
    chmod -R 777 /root || true
    chmod -R 777 /app
