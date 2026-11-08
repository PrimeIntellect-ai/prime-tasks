#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo
    ln -s /opt/cargo/bin/* /usr/local/bin/

    # Create project files
    mkdir -p /home/user/math_project/src
    mkdir -p /home/user/math_project/math_encoder

    cat << 'EOF' > /home/user/math_project/Cargo.toml
[package]
name = "rs_math"
version = "0.1.0"
edition = "2021"

[lib]
name = "rs_math"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.18.3", features = ["extension-module"] }
EOF

    cat << 'EOF' > /home/user/math_project/src/lib.rs
use pyo3::prelude::*;

#[pyfunction]
fn get_factors(n: u64) -> PyResult<Vec<u64>> {
    let mut factors = Vec::new();
    let mut num = n;
    let mut divisor = 2;
    while num > 1 {
        if num % divisor == 0 {
            factors.push(divisor);
            num /= divisor;
        } else {
            divisor += 1;
        }
    }

    let debug_msg = String::from("Calculation complete");
    let _moved_msg = debug_msg;
    // BORROW CHECKER BUG: Trying to use a moved value
    println!("Status: {}", debug_msg);

    Ok(factors)
}

#[pymodule]
fn rs_math(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(get_factors, m)?)?;
    Ok(())
}
EOF

    cat << 'EOF' > /home/user/math_project/setup.py
from setuptools import setup
from setuptools_rust import Binding, RustExtension

setup(
    name="math_encoder",
    version="0.1.0",
    packages=["math_encoder"],
    rust_extensions=[RustExtension("rs_math", binding=Binding.PyO3)],
    zip_safe=False,
)
EOF

    cat << 'EOF' > /home/user/math_project/math_encoder/__init__.py
# IMPORT ORDERING BUG: This currently causes an ImportError when tests run 
# because it attempts to import the encoder before the config is loaded.
from .encoder import encode_factors
from .config import init_config

init_config()
EOF

    cat << 'EOF' > /home/user/math_project/math_encoder/config.py
def init_config():
    global IS_INITIALIZED
    IS_INITIALIZED = True
EOF

    cat << 'EOF' > /home/user/math_project/math_encoder/encoder.py
import base64
import rs_math
import math_encoder.config

# Fails if config is not initialized first
if not getattr(math_encoder.config, 'IS_INITIALIZED', False):
    raise RuntimeError("Config not initialized before encoder import!")

def encode_factors(n: int) -> str:
    factors = rs_math.get_factors(n)
    factor_str = ",".join(map(str, factors))
    return base64.b32encode(factor_str.encode('utf-8')).decode('utf-8')
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
