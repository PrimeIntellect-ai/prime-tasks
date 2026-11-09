#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R a+rw $RUSTUP_HOME $CARGO_HOME

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_logs.txt
[2023-10-12 14:32:01] 192.168.1.10 - /api/v1/login - 200 - 45.2ms
[2023-10-12 14:32:02] 10.0.0.5 - /api/v1/data - 200 - 120.5ms
[2023-10-12 14:32:03] 192.168.1.11 - /api/v1/login - 200 - 50.1ms
[2023-10-12 14:32:04] 172.16.0.2 - /api/v1/upload - 201 - 340.0ms
[2023-10-12 14:32:05] 10.0.0.5 - /api/v1/data - 500 - 500.0ms
[2023-10-12 14:32:06] 192.168.1.12 - /api/v1/login - 200 - 47.8ms
[2023-10-12 14:32:07] 172.16.0.3 - /api/v1/upload - 201 - 355.5ms
[2023-10-12 14:32:08] 10.0.0.6 - /api/v1/data - 200 - 118.0ms
[2023-10-12 14:32:09] 192.168.1.10 - /api/v1/login - 200 - 46.5ms
[2023-10-12 14:32:10] 172.16.0.4 - /api/v1/upload - 500 - 400.0ms
[2023-10-12 14:32:11] 10.0.0.7 - /api/v1/data - 200 - 122.3ms
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
