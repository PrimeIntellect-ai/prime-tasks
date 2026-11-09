#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust/rustup
    export CARGO_HOME=/opt/rust/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="$CARGO_HOME/bin:$PATH"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create raw data
    cat << 'EOF' > /home/user/telemetry_raw.csv
timestamp,sensor_data
1700000100,"temp_val=10.0"
1700000101,"val=12.0C"
1700000103,"[WARN] val=12.0"
1700000104,"val=15.0"
1700000107,"ERR: val=18.0"
EOF

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /opt/rust
