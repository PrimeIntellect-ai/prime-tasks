#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    # Create acl-manager-rs
    mkdir -p /app/acl-manager-rs/src
    cat << 'EOF' > /app/acl-manager-rs/Cargo.toml
[package]
name = "acl-manager-rs"
version = "0.2.1"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/acl-manager-rs/build.rs
fn main() {
    let _mode = std::env::var("ACL_BUILD_MODE").unwrap();
}
EOF

    cat << 'EOF' > /app/acl-manager-rs/src/lib.rs
pub fn dry_run_acl() -> bool { true }
EOF

    # Create corpora
    mkdir -p /app/corpora/clean /app/corpora/evil

    cat << 'EOF' > /app/corpora/clean/valid1.json
{"username": "alice_smith", "quota_mb": 500, "ssh_key": "ssh-ed25519 AAAAC3... user", "sync_ip": "10.0.0.5"}
EOF

    cat << 'EOF' > /app/corpora/evil/bad1.json
{"username": "../root", "quota_mb": 500, "ssh_key": "ssh-rsa AAAAB3... user", "sync_ip": "10.0.0.5"}
EOF

    cat << 'EOF' > /app/corpora/evil/bad2.json
{"username": "bob", "quota_mb": -100, "ssh_key": "ssh-rsa AAAAB3... user", "sync_ip": "10.0.0.5"}
EOF

    cat << 'EOF' > /app/corpora/evil/bad3.json
{"username": "charlie", "quota_mb": 500, "ssh_key": "ssh-rsa AAAAB3; rm -rf /", "sync_ip": "10.0.0.5"}
EOF

    cat << 'EOF' > /app/corpora/evil/bad4.json
{"username": "dave", "quota_mb": 500, "ssh_key": "ssh-rsa AAA", "sync_ip": "999.999.999.999"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
