#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rustup /opt/cargo
    ln -s /opt/cargo/bin/* /usr/local/bin/

    # Create user
    useradd -m -s /bin/bash user || true

    # Create data directory and interactions.csv
    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/interactions.csv
0.5,0.2,0.1,0.0,0.0
0.1,0.6,0.2,0.1,0.0
0.0,0.1,0.7,0.2,0.1
0.0,0.0,0.1,0.5,0.2
0.0,0.0,0.0,0.1,0.4
EOF

    # Set permissions
    chmod -R 777 /home/user
