#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest maturin hypothesis

    mkdir -p /home/user/release_prep/rust_ext/src
    mkdir -p /home/user/release_prep/num_cruncher

    cat << 'EOF' > /home/user/release_prep/rust_ext/Cargo.toml
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

    cat << 'EOF' > /home/user/release_prep/rust_ext/pyproject.toml
[build-system]
requires = ["maturin>=1.0,<2.0"]
build-backend = "maturin"

[project]
name = "rust_ext"
version = "0.1.0"
EOF

    cat << 'EOF' > /home/user/release_prep/rust_ext/src/lib.rs
use pyo3::prelude::*;

#[pyfunction]
fn scale_and_append(mut values: Vec<f64>, factor: f64) -> PyResult<Vec<f64>> {
    if values.is_empty() {
        return Ok(values);
    }
    // BUG: borrow checker error
    let first = &values[0];
    values.push(*first * factor); // mutable borrow while immutable borrow exists

    let mut res = Vec::new();
    for v in values.iter() {
        res.push(v * factor);
    }
    Ok(res)
}

#[pymodule]
fn rust_ext(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(scale_and_append, m)?)?;
    Ok(())
}
EOF

    touch /home/user/release_prep/num_cruncher/__init__.py

    cat << 'EOF' > /home/user/release_prep/num_cruncher/ci_logger.py
import sys

def init_logger():
    # Mocking a strange CI patch that breaks Rust extensions if loaded first
    sys.stdout.write("CI Logger Initialized\n")
    sys.modules['__main__'].__logger_patched__ = True
EOF

    cat << 'EOF' > /home/user/release_prep/test_runner.py
import sys

# Import Order Bug: importing ci_logger before rust_ext simulates a failure
from num_cruncher import ci_logger
ci_logger.init_logger()

# If rust_ext is imported after ci_logger sets __logger_patched__, simulate crash
if getattr(sys.modules.get('__main__'), '__logger_patched__', False):
    print("FATAL ERROR: Rust extension loaded after CI logger patch!")
    sys.exit(1)

import rust_ext

def test_basic():
    res = rust_ext.scale_and_append([1.0, 2.0], 2.0)
    assert len(res) == 3

if __name__ == "__main__":
    test_basic()
    print("Tests passed!")
EOF

    cat << 'EOF' > /home/user/release_prep/ci_data.json
{
  "project": "num_cruncher",
  "raw_metrics": [10.5, 20.1, 5.0, 8.2]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
