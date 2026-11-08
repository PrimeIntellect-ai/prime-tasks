#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc libsqlite3-dev cargo
    pip3 install pytest

    mkdir -p /home/user/graph_processor/src
    cd /home/user/graph_processor
    cat << 'EOF' > Cargo.toml
[package]
name = "graph_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = { version = "0.29.0", features = ["bundled"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > src/main.rs
use std::sync::{Arc, Mutex};
use std::thread;

fn main() {
    // Deliberately broken/deadlocking stub
    println!("Please implement the graph processor.");
}
EOF

    cat << 'EOF' > /home/user/dataset.jsonl
{"researcher": "Alice", "collaborators": ["Bob", "Charlie", "Dave"]}
{"researcher": "Bob", "collaborators": ["Eve", "Frank"]}
{"researcher": "Charlie", "collaborators": ["Dave"]}
{"researcher": "Frank", "collaborators": ["Alice", "Grace"]}
{"researcher": "Grace", "collaborators": ["Heidi"]}
{"researcher": "Dave", "collaborators": ["Eve"]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
