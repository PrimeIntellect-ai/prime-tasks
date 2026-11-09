#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/release_manager/src

    cat << 'EOF' > /home/user/release_manager/Cargo.toml
[package]
name = "release_checker"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
sha2 = "0.10"
EOF

    cat << 'EOF' > /home/user/release_manager/src/main.rs
use sha2::{Sha256, Digest};
use serde::Deserialize;
use std::fs;
use std::env;

#[derive(Deserialize)]
struct Manifest {
    version: String,
    data: String,
    checksum: String,
}

// BUG: Lifetime/ownership issue. Takes a String, but tries to return a reference to it.
fn get_version_ref(v: String) -> &str {
    &v
}

fn compare_versions(new_ver: &str, old_ver: &str) -> bool {
    let new_parts: Vec<&str> = new_ver.split('.').collect();
    let old_parts: Vec<&str> = old_ver.split('.').collect();

    let n_major: u32 = new_parts[0].parse().unwrap_or(0);
    let o_major: u32 = old_parts[0].parse().unwrap_or(0);
    if n_major > o_major { return true; }
    if n_major < o_major { return false; }

    let n_minor: u32 = new_parts[1].parse().unwrap_or(0);
    let o_minor: u32 = old_parts[1].parse().unwrap_or(0);
    if n_minor > o_minor { return true; }
    if n_minor < o_minor { return false; }

    let n_patch: u32 = new_parts[2].parse().unwrap_or(0);
    let o_patch: u32 = old_parts[2].parse().unwrap_or(0);

    n_patch > o_patch
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        eprintln!("Usage: {} <manifest_path> <previous_version>", args[0]);
        std::process::exit(1);
    }

    let manifest_path = &args[1];
    let previous_version = &args[2];

    let content = fs::read_to_string(manifest_path).expect("Failed to read manifest");
    let manifest: Manifest = serde_json::from_str(&content).expect("Failed to parse JSON");

    // Checksum verify
    let mut hasher = Sha256::new();
    hasher.update(manifest.data.as_bytes());
    let result = hasher.finalize();
    let computed_hash = format!("{:x}", result);

    if computed_hash != manifest.checksum {
        println!("FAIL: CHECKSUM");
        return;
    }

    // Version verify
    let new_v_ref = get_version_ref(manifest.version); // ERROR HERE
    if !compare_versions(new_v_ref, previous_version) {
        println!("FAIL: DOWNGRADE");
        return;
    }

    println!("PASS");
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
