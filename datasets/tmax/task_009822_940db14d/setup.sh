#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo
    export PATH="/opt/cargo/bin:${PATH}"

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,x,y,z
2023-10-01T10:00:00Z,1.0,2.0,2.0
2023-10-01T10:01:00Z,0.0,0.0,0.0
2023-10-01T10:02:00Z,3.0,4.0,12.0
2023-10-01T10:03:00Z,invalid,1.0,1.0
2023-10-01T10:04:00Z,0.5,0.5,0.7071067811865476
2023-10-01T10:05:00Z,-6.0,8.0,0.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
