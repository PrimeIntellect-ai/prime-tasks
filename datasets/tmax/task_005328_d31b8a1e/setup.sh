#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest maturin hypothesis

    mkdir -p /home/user/project/src

    cat << 'EOF' > /home/user/project/Cargo.toml
[package]
name = "data_processor"
version = "0.1.0"
edition = "2021"

[lib]
name = "data_processor"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    cat << 'EOF' > /home/user/project/pyproject.toml
[build-system]
requires = ["maturin>=1.0,<2.0"]
build-backend = "maturin"

[project]
name = "data_processor"
version = "0.1.0"
requires-python = ">=3.7"
EOF

    cat << 'EOF' > /home/user/project/src/lib.rs
use pyo3::prelude::*;
use std::collections::HashSet;

#[pyfunction]
fn process_data(data: Vec<i32>) -> PyResult<Vec<i32>> {
    let mut set: HashSet<i32> = HashSet::new();
    for item in data {
        set.insert(item);
    }
    let mut vec: Vec<i32> = set.into_iter().collect();
    vec.sort()
    Ok(vec)
}

#[pymodule]
fn data_processor(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(process_data, m)?)?;
    Ok(())
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
