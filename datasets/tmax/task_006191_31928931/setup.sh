#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential tar gzip
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /opt/rust /opt/cargo
    export PATH=/opt/cargo/bin:$PATH

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/incoming /home/user/archive_dest

    # Create log files and archives
    cd /tmp
    printf "2020: System initialized smoothly.\n" > app_2020.log
    printf "2021: Admin logged in.\n" > auth_2021.log

    tar -czf logs_2020.tar.gz app_2020.log
    tar -czf logs_2021.tar.gz auth_2021.log

    tar -czf /home/user/incoming/nested_logs.tar.gz logs_2020.tar.gz logs_2021.tar.gz

    # Cleanup and permissions
    rm -f /tmp/app_2020.log /tmp/auth_2021.log /tmp/logs_2020.tar.gz /tmp/logs_2021.tar.gz
    chmod -R 777 /home/user
