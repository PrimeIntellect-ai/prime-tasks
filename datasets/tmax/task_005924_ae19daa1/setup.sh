#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 rustc cargo
    pip3 install pytest

    mkdir -p /home/user/graph_tool/src

    cat << 'EOF' > /home/user/graph_tool/Cargo.toml
[package]
name = "graph_tool"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = { version = "0.31.0", features = ["bundled"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/graph_tool/src/main.rs
fn main() {
    println!("Implement me!");
}
EOF

    sqlite3 /home/user/graph_tool/graph.db << 'EOF'
CREATE TABLE edges (source TEXT, target TEXT);
INSERT INTO edges (source, target) VALUES 
('START', 'A'),
('A', 'B'),
('B', 'C'),
('C', 'END'),
('START', 'X'),
('X', 'Y'),
('Y', 'END'),
('START', 'M'),
('M', 'END'),
('M', 'NOPE');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
