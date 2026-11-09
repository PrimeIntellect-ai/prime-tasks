#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    # Create directories
    mkdir -p /home/user/citation_graph/data
    mkdir -p /home/user/citation_graph/src

    # Create Cargo.toml
    cat << 'EOF' > /home/user/citation_graph/Cargo.toml
[package]
name = "citation_graph"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    # Create papers.jsonl
    cat << 'EOF' > /home/user/citation_graph/data/papers.jsonl
{"id": "P001", "title": "Intro to AI", "references": ["P002", "P005"]}
{"id": "P002", "title": "Advanced ML", "references": ["P005"]}
{"id": "P003", "title": "Data Science", "references": ["P001", "P005", "P002"]}
{"id": "P004", "title": "Graph DBs", "references": ["P003", "P005"]}
{"id": "P005", "title": "Deep Learning", "references": []}
{"id": "P006", "title": "Transformers", "references": ["P005", "P002"]}
EOF

    # Set up user and permissions
    useradd -m -s /bin/bash user || true

    # Ensure rust is available for all users
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup

    cat << 'EOF' >> /home/user/.bashrc
export PATH="/home/user/.cargo/bin:$PATH"
EOF

    chmod -R 777 /home/user
