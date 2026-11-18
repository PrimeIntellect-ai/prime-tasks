#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/monitor_workspace/api/src
    mkdir -p /home/user/monitor_workspace/core/src

    cat << 'EOF' > /home/user/monitor_workspace/Cargo.toml
[workspace]
members = ["api", "core"]
resolver = "2"
EOF

    cat << 'EOF' > /home/user/monitor_workspace/api/Cargo.toml
[package]
name = "api"
version = "0.1.0"
edition = "2021"

[dependencies]
core = { path = "../core" }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/monitor_workspace/api/src/lib.rs
use serde::Serialize;
use core::read_uptime;

#[derive(Serialize)]
pub struct UptimeResponse {
    pub uptime: f64,
}

pub fn get_uptime_json() -> String {
    // Note: The agent will need to update this to pass the proc_dir
    let val = read_uptime(); 
    let resp = UptimeResponse { uptime: val };
    serde_json::to_string(&resp).unwrap()
}
EOF

    cat << 'EOF' > /home/user/monitor_workspace/core/Cargo.toml
[package]
name = "core"
version = "0.1.0"
edition = "2021"

[dependencies]
api = { path = "../api" }
EOF

    cat << 'EOF' > /home/user/monitor_workspace/core/src/lib.rs
use std::fs;
use api::UptimeResponse; // Circular dependency here!

pub fn read_uptime() -> f64 {
    let contents = fs::read_to_string("/proc/uptime").unwrap();
    let parts: Vec<&str> = contents.split_whitespace().collect();
    parts[0].parse::<f64>().unwrap()
}

pub fn create_response() -> UptimeResponse {
    UptimeResponse { uptime: read_uptime() }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
