#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/rust_rate_limiter/src
    cd /home/user/rust_rate_limiter

    cat << 'EOF' > Cargo.toml
[package]
name = "rust_rate_limiter"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > src/lib.rs
use std::sync::atomic::{AtomicUsize, Ordering};

static CALL_COUNT: AtomicUsize = AtomicUsize::new(0);

// BUG 1: Missing no_mangle attribute
// BUG 2: Missing extern C
// BUG 3: Syntax error (missing semicolon on let statement)
pub fn check_rate_limit(user_id: i32) -> bool {
    if user_id != 42 { return false; }
    let count = CALL_COUNT.fetch_add(1, Ordering::SeqCst)
    if count < 10 {
        true
    } else {
        false
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
