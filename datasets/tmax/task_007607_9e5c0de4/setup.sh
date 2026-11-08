#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential patch
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create directories
    mkdir -p /home/user/release_prep/core/src
    mkdir -p /home/user/release_prep/patches
    mkdir -p /home/user/release_prep/config

    # Create Cargo.toml
    cat << 'EOF' > /home/user/release_prep/core/Cargo.toml
[package]
name = "core"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    # Create lib.rs
    cat << 'EOF' > /home/user/release_prep/core/src/lib.rs
pub struct Config {
    pub name: String,
}

pub fn get_config_name(config: &Config) -> String {
    let name = config.name; // ERROR: cannot move out of `config.name` which is behind a shared reference
    name
}
EOF

    # Create deploy_rules.txt
    cat << 'EOF' > /home/user/release_prep/deploy_rules.txt
(coverage >= 80) AND (tests_passed == true) AND (lint_errors == 0)
EOF

    # Create metrics.json
    cat << 'EOF' > /home/user/release_prep/metrics.json
{
  "coverage": 85,
  "tests_passed": true,
  "lint_errors": 0
}
EOF

    # Create settings.ini
    cat << 'EOF' > /home/user/release_prep/config/settings.ini
[database]
host = localhost
port = 5432

[cache]
enabled = false
EOF

    # Create patches
    cat << 'EOF' > /home/user/release_prep/patches/01-update-db.diff
--- settings.ini
+++ settings.ini
@@ -1,3 +1,3 @@
 [database]
-host = localhost
+host = db.internal
 port = 5432
EOF

    cat << 'EOF' > /home/user/release_prep/patches/02-update-cache.diff
--- settings.ini
+++ settings.ini
@@ -3,2 +3,2 @@
 [cache]
-enabled = false
+enabled = true
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true

    # Make rust available for all users
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup

    # Ensure correct ownership and permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
