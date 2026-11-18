#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl build-essential
pip3 install pytest

# Install Rust globally so it's available to all users
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
chmod -R 777 /opt/rust
ln -s /opt/rust/bin/* /usr/local/bin/

# Create user
useradd -m -s /bin/bash user || true

# Ensure permissions are set
chmod -R 777 /home/user
