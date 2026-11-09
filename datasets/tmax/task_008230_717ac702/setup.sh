#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create dummy vulnerable crate
    mkdir -p /home/user/dummy-vulnerable-crate/src
    cat << 'EOF' > /home/user/dummy-vulnerable-crate/Cargo.toml
[package]
name = "dummy-vulnerable-crate"
version = "0.1.0"
edition = "2021"
EOF
    touch /home/user/dummy-vulnerable-crate/src/lib.rs

    # Create workspace structure
    mkdir -p /home/user/ci_workspace/crates/api/src
    mkdir -p /home/user/ci_workspace/crates/auth/src
    mkdir -p /home/user/ci_workspace/crates/db/src
    mkdir -p /home/user/ci_workspace/crates/ui/src
    mkdir -p /home/user/ci_workspace/crates/utils/src

    cat << 'EOF' > /home/user/ci_workspace/Cargo.toml
[workspace]
members = ["crates/*"]
resolver = "2"
EOF

    # crate: utils (no dependencies)
    cat << 'EOF' > /home/user/ci_workspace/crates/utils/Cargo.toml
[package]
name = "utils"
version = "0.1.0"
edition = "2021"
EOF
    touch /home/user/ci_workspace/crates/utils/src/lib.rs

    # crate: auth (depends on dummy-vulnerable-crate)
    cat << 'EOF' > /home/user/ci_workspace/crates/auth/Cargo.toml
[package]
name = "auth"
version = "0.1.0"
edition = "2021"

[dependencies]
dummy-vulnerable-crate = { path = "../../../dummy-vulnerable-crate" }
EOF
    touch /home/user/ci_workspace/crates/auth/src/lib.rs

    # crate: db (depends on dummy-vulnerable-crate)
    cat << 'EOF' > /home/user/ci_workspace/crates/db/Cargo.toml
[package]
name = "db"
version = "0.1.0"
edition = "2021"

[dependencies]
dummy-vulnerable-crate = { path = "../../../dummy-vulnerable-crate" }
EOF
    touch /home/user/ci_workspace/crates/db/src/lib.rs

    # crate: api (depends on auth -> transitively depends on dummy-vulnerable-crate)
    cat << 'EOF' > /home/user/ci_workspace/crates/api/Cargo.toml
[package]
name = "api"
version = "0.1.0"
edition = "2021"

[dependencies]
auth = { path = "../auth" }
EOF
    touch /home/user/ci_workspace/crates/api/src/lib.rs

    # crate: ui (depends on api -> transitively depends on dummy-vulnerable-crate)
    cat << 'EOF' > /home/user/ci_workspace/crates/ui/Cargo.toml
[package]
name = "ui"
version = "0.1.0"
edition = "2021"

[dependencies]
api = { path = "../api" }
EOF
    cat << 'EOF' > /home/user/ci_workspace/crates/ui/src/lib.rs
#[cfg(test)]
mod tests {
    #[test]
    fn test_ui_render() {
        assert_eq!(2 + 2, 5); // Agent must fix this to 4
    }
}
EOF

    # Make rust available to user
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup

    chown -R user:user /home/user
    chmod -R 777 /home/user
