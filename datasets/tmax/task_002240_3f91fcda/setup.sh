#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    # Create directories
    mkdir -p /app/dep-analyzer-core/src
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Create Rust project files
    cat << 'EOF' > /app/dep-analyzer-core/Cargo.toml
[package]
name = "dep-analyzer-core"
version = "1.2.0"
edition = "2021"
EOF

    cat << 'EOF' > /app/dep-analyzer-core/src/main.rs
mod graph;
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.contains(&String::from("--generate-samples")) {
        println!("Samples generated.");
    }
}
EOF

    cat << 'EOF' > /app/dep-analyzer-core/src/graph.rs
pub struct Node {
    pub id: String,
}

pub fn traverse_nodes(nodes: &Vec<Node>) -> Vec<&Node> {
    let local_node = Node { id: "local".to_string() };
    vec![&local_node]
}
EOF

    # Generate corpora using a quick Python script
    python3 -c '
import json, os

for i in range(20):
    with open(f"/home/user/corpora/clean/clean_{i}.json", "w") as f:
        json.dump({"deps": [["A", "B"]], "mem": [10, 5, 20, 15, 30]}, f)

for i in range(10):
    with open(f"/home/user/corpora/evil/evil_cycle_{i}.json", "w") as f:
        json.dump({"deps": [["A", "B"], ["B", "C"], ["C", "A"]], "mem": [10, 5, 20]}, f)

for i in range(10):
    with open(f"/home/user/corpora/evil/evil_mem_{i}.json", "w") as f:
        json.dump({"deps": [["A", "B"]], "mem": [10, 20, 30, 40, 50, 60]}, f)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
