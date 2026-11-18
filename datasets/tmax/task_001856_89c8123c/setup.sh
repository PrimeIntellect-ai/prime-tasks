#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    # Create virtual environment and install maturin
    python3 -m venv /opt/venv
    /opt/venv/bin/pip install maturin hypothesis pytest

    # Create directories
    mkdir -p /app/tlv_parser/src
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Create dummy legacy processor
    echo '#!/bin/sh' > /app/legacy_processor
    echo 'echo "Legacy processor"' >> /app/legacy_processor
    chmod +x /app/legacy_processor

    # Create PyO3 project
    cat << 'EOF' > /app/tlv_parser/Cargo.toml
[package]
name = "tlv_parser"
version = "0.1.0"
edition = "2021"

[lib]
name = "tlv_parser"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    cat << 'EOF' > /app/tlv_parser/src/lib.rs
use pyo3::prelude::*;

#[pyclass]
struct TlvNode {
    #[pyo3(get)]
    tag: u8,
    #[pyo3(get)]
    value: &str, // ERROR: missing lifetime specifier
}

#[pymodule]
fn tlv_parser(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_class::<TlvNode>()?;
    Ok(())
}
EOF

    # Create dummy corpora
    for i in $(seq 1 5); do
        echo "evil data $i" > /app/corpora/evil/evil_$i.bin
        echo "clean data $i" > /app/corpora/clean/clean_$i.bin
    done

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /opt/venv
