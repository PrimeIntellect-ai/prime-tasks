#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust globally
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    ln -s /opt/cargo/bin/* /usr/local/bin/

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /opt/rust /opt/cargo
    chmod -R 777 /home/user
