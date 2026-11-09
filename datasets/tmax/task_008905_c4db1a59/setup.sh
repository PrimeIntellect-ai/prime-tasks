#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories and files
    python3 -c '
import os

os.makedirs("/home/user/raw_data/subset_A", exist_ok=True)
os.makedirs("/home/user/raw_data/subset_B", exist_ok=True)
os.makedirs("/home/user/processed_data", exist_ok=True)

with open("/home/user/raw_data/file1.dat", "wb") as f:
    f.write(bytes([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0xE9, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65]))

with open("/home/user/raw_data/subset_A/file2.dat", "wb") as f:
    f.write(bytes([0x44, 0x61, 0x74, 0x61, 0x20, 0xF1, 0x6F]))

os.symlink("/home/user/raw_data", "/home/user/raw_data/subset_B/loop_link")
'

    # Set permissions
    chmod -R 777 /home/user
