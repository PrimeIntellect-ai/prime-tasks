#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/logs
    cat << 'EOF' > /home/user/logs/access.log
192.168.1.50 - GET /login?username=alice&redirect_url=https://trusted.corp/dashboard
192.168.1.51 - GET /login?username=bob&redirect_url=https://trusted.corp/settings
203.0.113.88 - GET /login?username=admin&redirect_url=http://evil.com/steal
192.168.1.52 - GET /login?username=charlie&redirect_url=https://trusted.corp/profile
EOF

    mkdir -p /home/user/auth_service/src

    cat << 'EOF' > /home/user/auth_service/Cargo.toml
[package]
name = "auth_service"
version = "0.1.0"
edition = "2021"

[dependencies]
sha2 = "0.10.8"
EOF

    cat << 'EOF' > /home/user/auth_service/src/lib.rs
pub mod auth;
EOF

    cat << 'EOF' > /home/user/auth_service/src/auth.rs
use sha2::{Sha256, Digest};

pub fn get_safe_redirect(requested_url: &str) -> String {
    requested_url.to_string()
}

pub fn generate_secure_token(username: &str) -> String {
    format!("{}_token", username)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
