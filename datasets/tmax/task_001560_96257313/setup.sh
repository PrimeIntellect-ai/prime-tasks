#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust globally
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_metrics.csv
config,cpu_util,mem_util,latency_ms
A,50.0,60.0,120.0
A,55.0,65.0,125.0
A,45.0,55.0,115.0
A,60.0,70.0,130.0
A,40.0,50.0,110.0
B,40.0,50.0,90.0
B,42.0,52.0,95.0
B,38.0,48.0,85.0
B,45.0,55.0,100.0
B,35.0,45.0,80.0
EOF

    chmod -R 777 /home/user
