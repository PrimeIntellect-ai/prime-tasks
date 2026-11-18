#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create project structure
    mkdir -p /home/user/rust_pipeline/src
    mkdir -p /home/user/rust_pipeline/tests

    cat << 'EOF' > /home/user/rust_pipeline/Cargo.toml
[package]
name = "rust_pipeline"
version = "0.1.0"
edition = "2021"

[features]
default = []
fast_asm = []
EOF

    cat << 'EOF' > /home/user/rust_pipeline/src/lib.rs
pub mod schema;
pub mod asm_parser;
EOF

    cat << 'EOF' > /home/user/rust_pipeline/src/schema.rs
pub struct RecordV1 {
    pub id: u32,
    pub payload: String,
}

pub struct RecordV2 {
    pub id: u32,
    pub payload: String,
    pub processed_timestamp: u64,
}

pub fn migrate(v1: RecordV1) -> RecordV2 {
    RecordV2 {
        id: v1.id,
        payload: v1.payload,
        processed_timestamp: std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs(),
    }
}
EOF

    cat << 'EOF' > /home/user/rust_pipeline/src/asm_parser.rs
#[cfg(all(feature = "fast_asm", target_arch = "x86-64"))] // BUG: Should be x86_64
use std::arch::asm;

#[cfg(all(feature = "fast_asm", target_arch = "x86_64"))]
pub fn get_magic_number() -> u64 {
    let magic: u64;
    unsafe {
        asm!(
            "",
            out(reg) magic
        );
    }
    magic
}

#[cfg(not(all(feature = "fast_asm", target_arch = "x86_64")))]
pub fn get_magic_number() -> u64 {
    42
}
EOF

    cat << 'EOF' > /home/user/rust_pipeline/tests/migration_tests.rs
use rust_pipeline::schema::{RecordV1, RecordV2, migrate};
use rust_pipeline::asm_parser::get_magic_number;

#[test]
fn test_migration() {
    let mock_v1 = RecordV1 {
        id: 1,
        payload: "test_data".to_string(),
    };

    let result = migrate(mock_v1);
    assert_eq!(result.id, 1);
    assert_eq!(result.payload, "test_data");

    // Test compilation failure below:
    let _mock_v2_expected = RecordV2 {
        id: 1,
        payload: "test_data".to_string(),
        // BUG: Missing timestamp field
    };
}

#[test]
fn test_asm_magic() {
    assert_eq!(get_magic_number(), 42);
}
EOF

    # Setup permissions and Rust environment for user
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup
    chown -R user:user /home/user/.cargo /home/user/.rustup

    cat << 'EOF' >> /home/user/.bashrc
export PATH="/home/user/.cargo/bin:${PATH}"
EOF

    chmod -R 777 /home/user
