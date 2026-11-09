#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest setuptools wheel

    mkdir -p /home/user/fastparser_ext/src

    cat << 'EOF' > /home/user/fastparser_ext/pyproject.toml
[build-system]
requires = ["setuptools", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "fastparser"
version = "0.1.0"
EOF

    cat << 'EOF' > /home/user/fastparser_ext/setup.py
from setuptools import setup
from setuptools_rust import Binding, RustExtension

setup(
    name="fastparser",
    version="0.1.0",
    rust_extensions=[RustExtension("fastparser", binding=Binding.PyO3)],
    zip_safe=False,
)
EOF

    cat << 'EOF' > /home/user/fastparser_ext/Cargo.toml
[package]
name = "fastparser"
version = "0.1.0"
edition = "2021"

[lib]
name = "fastparser"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    cat << 'EOF' > /home/user/fastparser_ext/src/lib.rs
use pyo3::prelude::*;

#[pyfunction]
fn parse_custom_protocol(input: String) -> PyResult<Vec<String>> {
    let mut results = Vec::new();
    let mut current_token = String::new();
    let mut state = 0;

    for c in input.chars() {
        if state == 0 {
            if c != '|' {
                current_token.push(c);
                state = 1;
            }
        } else if state == 1 {
            if c == '|' {
                let token = current_token;
                results.push(token);
                current_token.clear(); // Borrow checker error: value borrowed here after move
                state = 0;
            } else {
                current_token.push(c);
            }
        }
    }
    if state == 1 {
        results.push(current_token);
    }
    Ok(results)
}

#[pymodule]
fn fastparser(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(parse_custom_protocol, m)?)?;
    Ok(())
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
