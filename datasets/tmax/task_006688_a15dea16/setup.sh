#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential tar
    pip3 install pytest

    # Install Rust toolchain globally
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    ln -s /opt/cargo/bin/* /usr/local/bin/

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure correct permissions
    chmod -R 777 /home/user
    chmod -R 777 /opt/cargo
    chmod -R 777 /opt/rust
