#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-dev \
        build-essential \
        cargo \
        rustc

    pip3 install pytest maturin

    mkdir -p /app/vendored/ci-log-decoder/src

    cat << 'EOF' > /app/vendored/ci-log-decoder/pyproject.toml
[build-system]
requires = ["setuptools"]
build-backend = "setuptools.build_meta"

[project]
name = "ci-log-decoder"
version = "0.1.0"
EOF

    cat << 'EOF' > /app/vendored/ci-log-decoder/Cargo.toml
[package]
name = "ci-log-decoder"
version = "0.1.0"
edition = "2021"

[lib]
name = "ci_log_decoder"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    cat << 'EOF' > /app/vendored/ci-log-decoder/src/lib.rs
use pyo3::prelude::*;
use pyo3::exceptions::PyValueError;

#[pyfunction]
fn decode_log(data: &[u8]) -> PyResult<Vec<String>> {
    let mut results: Vec<&str> = Vec::new();
    let mut i = 0;
    while i < data.len() {
        if data[i] == 0x02 {
            i += 1;
            if i < data.len() {
                let len = data[i] as usize;
                i += 1;
                if i + len <= data.len() {
                    let slice = &data[i..i+len];
                    let s = String::from_utf8_lossy(slice).into_owned();
                    // Borrow checker error: s is dropped at the end of the loop
                    results.push(s.as_str());
                    i += len;
                    if i < data.len() && data[i] == 0x03 {
                        i += 1;
                        continue;
                    }
                }
            }
        }
        return Err(PyValueError::new_err("Invalid encoding"));
    }

    Ok(results.iter().map(|&s| s.to_string()).collect())
}

#[pymodule]
fn ci_log_decoder(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(decode_log, m)?)?;
    Ok(())
}
EOF

    # Pre-fetch crates so air-gapped build works
    cd /app/vendored/ci-log-decoder
    cargo fetch || true

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
