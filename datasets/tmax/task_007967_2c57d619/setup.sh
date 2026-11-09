#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Make rust available to all users
    cp -r /root/.cargo /usr/local/cargo
    cp -r /root/.rustup /usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    export RUSTUP_HOME=/usr/local/rustup
    export PATH="${CARGO_HOME}/bin:${PATH}"
    echo 'export PATH="/usr/local/cargo/bin:${PATH}"' >> /etc/profile

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /usr/local/cargo
    chmod -R 777 /usr/local/rustup
