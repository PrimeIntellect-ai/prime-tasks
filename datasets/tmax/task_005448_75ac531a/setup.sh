#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    # Create base configs
    mkdir -p /tmp/base_setup
    printf "host=localhost\nport=5432\n" > /tmp/base_setup/db.conf
    printf "theme=dark\n" > /tmp/base_setup/app.conf
    printf "log_level=info\n" > /tmp/base_setup/log.conf

    # Create the base archive
    mkdir -p /home/user
    cd /tmp/base_setup && tar -czf /home/user/base_config.tar.gz db.conf app.conf log.conf

    # Create the current config directory
    mkdir -p /home/user/configs
    printf "host=localhost\nport=5432\n" > /home/user/configs/db.conf
    printf "theme=light\n" > /home/user/configs/app.conf
    printf "log_level=info\n" > /home/user/configs/log.conf
    printf "size=1024\n" > /home/user/configs/cache.conf

    # Create the Rust project manually to avoid network timeouts during build
    mkdir -p /home/user/config_manager/src
    cat << 'EOF' > /home/user/config_manager/Cargo.toml
[package]
name = "config_manager"
version = "0.1.0"
edition = "2021"

[dependencies]
tar = "0.4"
flate2 = "1.0"
EOF

    cat << 'EOF' > /home/user/config_manager/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
