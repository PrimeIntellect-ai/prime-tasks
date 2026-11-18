#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo nginx curl
    pip3 install pytest maturin hypothesis flask

    mkdir -p /home/user/workspace/rust_ext/src

    cat << 'EOF' > /home/user/workspace/rust_ext/Cargo.toml
[package]
name = "rust_ext"
version = "0.1.0"
edition = "2021"

[lib]
name = "rust_ext"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    cat << 'EOF' > /home/user/workspace/rust_ext/pyproject.toml
[build-system]
requires = ["maturin>=1.0,<2.0"]
build-backend = "maturin"

[project]
name = "rust_ext"
requires-python = ">=3.7"
classifiers = [
    "Programming Language :: Rust",
    "Programming Language :: Python :: Implementation :: CPython",
    "Programming Language :: Python :: Implementation :: PyPy",
]
EOF

    cat << 'EOF' > /home/user/workspace/rust_ext/src/lib.rs
use pyo3::prelude::*;

#[pyfunction]
fn process_string(s: String) -> PyResult<String> {
    let r1 = &s;
    let mut mut_s = s; // BORROW CHECKER ERROR: cannot move out of `s` because it is borrowed
    mut_s.push_str(r1);
    Ok(mut_s)
}

#[pymodule]
fn rust_ext(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(process_string, m)?)?;
    Ok(())
}
EOF

    cat << 'EOF' > /home/user/workspace/app.py
from flask import Flask, request
import rust_ext

app = Flask(__name__)

@app.route('/process')
def process():
    text = request.args.get('text', '')
    return rust_ext.process_string(text)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
