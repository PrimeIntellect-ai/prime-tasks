#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl nginx build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

    useradd -m -s /bin/bash user || true

    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup
    chown -R user:user /home/user/.cargo /home/user/.rustup

    ln -s /home/user/.cargo/bin/cargo /usr/local/bin/cargo
    ln -s /home/user/.cargo/bin/rustc /usr/local/bin/rustc

    chmod -R 777 /home/user
