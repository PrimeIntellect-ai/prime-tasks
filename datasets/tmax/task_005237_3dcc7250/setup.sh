#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl nginx cargo rustc
    pip3 install pytest setuptools setuptools-rust

    # Create directories
    mkdir -p /app/vendored_package/mobile_asset_builder/src
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create vendored package files
    cat << 'EOF' > /app/vendored_package/mobile_asset_builder/Cargo.toml
[package]
name = "mobile_asset_builder"
version = "0.1.0"
edition = "2021"

[lib]
name = "mobile_asset_builder"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.18.3", features = ["extension-module"] }
EOF

    cat << 'EOF' > /app/vendored_package/mobile_asset_builder/pyproject.toml
[build-system]
requires = ["setuptools", "setuptools-rust"]
build-backend = "setuptools.build_meta"

[project]
name = "mobile_asset_builder"
version = "0.1.0"
EOF

    cat << 'EOF' > /app/vendored_package/mobile_asset_builder/setup.py
from setuptools import setup
from setuptools_rust import Binding, RustExtension

setup(
    name="mobile_asset_builder",
    version="0.1.0",
    rust_extensions=[RustExtension("mobile_asset_builder", binding=Binding.PyO3)],
    zip_safe=False,
)
EOF

    cat << 'EOF' > /app/vendored_package/mobile_asset_builder/src/lib.rs
use pyo3::prelude::*;

fn process_asset(name: &String) -> &str {
    let formatted = format!("{}_asset", name);
    return &formatted;
}

#[pyfunction]
fn process(name: String) -> PyResult<String> {
    let res = process_asset(&name);
    Ok(res.to_string())
}

#[pymodule]
fn mobile_asset_builder(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(process, m)?)?;
    Ok(())
}
EOF

    # Create corpus files
    python3 -c "
import os
import json
import base64

def write_corpus(path, data):
    with open(path, 'w') as f:
        f.write(base64.b64encode(json.dumps(data).encode('utf-16le')).decode('utf-8'))

write_corpus('/app/corpus/clean/1.txt', {'output_dir': 'build/outputs/'})
write_corpus('/app/corpus/evil/1.txt', {'output_dir': '../build/outputs/'})
"

    # Set up user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
