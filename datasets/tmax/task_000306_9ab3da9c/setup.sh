#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install Rust
    apt-get install -y cargo rustc

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure correct permissions
    chmod -R 777 /home/user
