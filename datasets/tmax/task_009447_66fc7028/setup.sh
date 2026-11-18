#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Install Rust for the user
    su - user -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"

    # Symlink to /usr/local/bin so it is globally available in PATH
    ln -s /home/user/.cargo/bin/cargo /usr/local/bin/cargo
    ln -s /home/user/.cargo/bin/rustc /usr/local/bin/rustc

    chmod -R 777 /home/user
