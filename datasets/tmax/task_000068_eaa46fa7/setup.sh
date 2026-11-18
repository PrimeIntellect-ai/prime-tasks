#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make cargo rustc
    pip3 install pytest

    mkdir -p /app/k8s-manifest-gen/src

    cat << 'EOF' > /app/k8s-manifest-gen/Cargo.toml
[package]
name = "k8s-manifest-gen"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/k8s-manifest-gen/Makefile
CARGO_BIN ?= /usr/bin/cargo-broken

build:
	$(CARGO_BIN) build --release
EOF

    cat << 'EOF' > /app/k8s-manifest-gen/src/main.rs
use std::fs;
use std::path::Path;

fn generate_deployment(svc: &str) -> String {
    format!("apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: {}\n---\n", svc)
}

fn main() {
    let mut result = String::new();
    let config_dir = Path::new("/home/user/configs");
    if let Ok(entries) = fs::read_dir(config_dir) {
        for entry in entries {
            if let Ok(entry) = entry {
                let file_name = entry.file_name().into_string().unwrap();
                if file_name.ends_with(".json") {
                    let svc = file_name.replace(".json", "");
                    for _ in 0..50 {
                        result.push_str(&generate_deployment(&svc));
                    }
                }
            }
        }
    }
    fs::write("/home/user/output/manifests.yaml", result).unwrap();
}
EOF

    mkdir -p /home/user/configs
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/configs/service1.json
{
    "name": "service1"
}
EOF

    cat << 'EOF' > /home/user/configs/service2.json
{
    "name": "service2"
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
