#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/mounter/src
    mkdir -p /home/user/state

    cat << 'EOF' > /home/user/mounter/Cargo.toml
[package]
name = "mounter"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/mounter/src/main.rs
use std::env;
use std::fs;

fn main() {
    let fstab_path = env::var("FSTAB_PATH").unwrap_or_else(|_| "/etc/fstab".to_string());

    // BUG: Hardcoded state dir overriding the environment
    let state_dir = "/tmp/state".to_string(); 

    let fstab_content = fs::read_to_string(&fstab_path)
        .expect("Failed to read fstab file");

    for line in fstab_content.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 3 {
            let fs_type = parts[0];
            let mount_point = parts[1];

            let log_msg = format!("Simulated mounting {} on {}", fs_type, mount_point);
            let log_path = format!("{}/mount_state.log", state_dir);

            // Create the hardcoded dir if it doesn't exist just to run, though it's wrong
            let _ = fs::create_dir_all(&state_dir);
            fs::write(log_path, log_msg).expect("Failed to write state log");
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
