#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    ln -s /opt/cargo/bin/* /usr/local/bin/

    # Create user
    useradd -m -s /bin/bash user || true

    # Create required files
    cat << 'EOF' > /home/user/features.csv
user_id,feature_a
1,0.2
2,0.6
3,0.8
4,0.9
5,0.4
6,0.7
7,0.55
EOF

    cat << 'EOF' > /home/user/labels.csv
user_id,label
1,0
2,1
3,
4,1
5,0
6,0
7,
EOF

    # Set permissions
    chmod -R 777 /opt/rust /opt/cargo
    chmod -R 777 /home/user
