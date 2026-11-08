#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc

    pip3 install pytest setuptools wheel setuptools-rust

    mkdir -p /home/user/log_parser_accel/src
    cd /home/user/log_parser_accel

    cat << 'EOF' > setup.py
from setuptools import setup
# Missing setuptools_rust imports and configuration

setup(
    name="log_parser_accel",
    version="0.1.0",
    packages=["log_parser_accel"],
    # Bug: The extension config is missing here
    zip_safe=False,
)
EOF

    cat << 'EOF' > pyproject.toml
[build-system]
requires = ["setuptools", "wheel", "setuptools-rust"]
build-backend = "setuptools.build_meta"
EOF

    cat << 'EOF' > Cargo.toml
[package]
name = "log_parser_accel"
version = "0.1.0"
edition = "2021"

[lib]
name = "log_parser_accel"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.18.3", features = ["extension-module"] }
EOF

    cat << 'EOF' > src/lib.rs
use pyo3::prelude::*;

#[pyclass]
pub struct LogEntry<'a> {
    #[pyo3(get)]
    pub level: &'a str,
    #[pyo3(get)]
    pub message: &'a str,
}

#[pyclass]
pub struct Parser {
    in_transaction: bool,
}

#[pymethods]
impl Parser {
    #[new]
    fn new() -> Self {
        Parser { in_transaction: false }
    }

    fn parse_line<'a>(&mut self, line: &'a str) -> Option<LogEntry<'a>> {
        if line.starts_with("BEGIN") {
            self.in_transaction = true;
            None
        } else if line.starts_with("END") {
            self.in_transaction = false;
            None
        } else if self.in_transaction && line.contains(":") {
            let parts: Vec<&str> = line.splitn(2, ':').collect();
            Some(LogEntry { level: parts[0].trim(), message: parts[1].trim() })
        } else {
            None
        }
    }
}

#[pymodule]
fn log_parser_accel(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_class::<Parser>()?;
    Ok(())
}
EOF

    cat << 'EOF' > /home/user/server.log
INFO: Booting up
BEGIN
ERROR: Disk full
WARN: High latency
END
DEBUG: Background task 1
BEGIN
INFO: User login successful
CRITICAL: Process crashed
END
EOF

    mkdir -p /home/user/log_parser_accel/log_parser_accel
    touch /home/user/log_parser_accel/log_parser_accel/__init__.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
