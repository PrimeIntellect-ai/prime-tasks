#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        curl \
        build-essential \
        pkg-config \
        libopenblas-dev \
        liblapack-dev \
        libfreetype6-dev \
        libfontconfig1-dev

    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /opt/rust /opt/cargo
    ln -s /opt/cargo/bin/* /usr/local/bin/

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
