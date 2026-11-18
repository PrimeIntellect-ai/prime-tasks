#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 curl build-essential libsqlite3-dev
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo
    ln -s /opt/cargo/bin/* /usr/local/bin/

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /home/user/graph_project/src

    # Create the SQLite DB
    sqlite3 /home/user/data/graph.db <<EOF
CREATE TABLE edges (id INTEGER PRIMARY KEY, source INTEGER, target INTEGER);
INSERT INTO edges (id, source, target) VALUES
(1, 100, 200),
(2, 200, 300),
(3, 300, 400),
(4, 150, 250),
(5, 250, 350);
EOF

    # Create the truth JSON
    cat <<EOF > /home/user/data/truth_edges.json
[
  {"id": 1, "source": 100, "target": 200},
  {"id": 2, "source": 200, "target": 300},
  {"id": 4, "source": 150, "target": 250}
]
EOF

    # Setup Rust project
    cat <<EOF > /home/user/graph_project/Cargo.toml
[package]
name = "graph_project"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = { version = "0.29.0", features = ["bundled"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat <<EOF > /home/user/graph_project/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
