#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust globally
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /opt/rust

    # Create workspace and data
    mkdir -p /workspace/data/dirA /workspace/data/dirB/nested /workspace/data/dirC
    touch /workspace/data/file_old.txt
    touch /workspace/data/file_new.txt
    touch /workspace/data/dirA/file_new_2.txt

    # Set specific times
    touch -d @1600000000 /workspace/data/file_old.txt
    touch -d @1750000000 /workspace/data/file_new.txt
    touch -d @1750000000 /workspace/data/dirA/file_new_2.txt

    # Create symlinks
    ln -s /workspace/data /workspace/data/dirA/loop_link
    ln -s /workspace/data/dirA /workspace/data/dirB/nested/link_to_A
    ln -s /workspace/data/dirC /workspace/data/dirC/self_loop

    # Create config
    cat << 'EOF' > /workspace/backup_config.json
{
  "sources": ["/workspace/data"],
  "destination": "/workspace/backup",
  "last_backup_time": 1700000000
}
EOF

    # Ensure workspace is accessible
    chmod -R 777 /workspace

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
