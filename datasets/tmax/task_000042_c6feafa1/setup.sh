#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /opt/rust /opt/cargo
    export PATH=/opt/cargo/bin:$PATH

    mkdir -p /app/route-auth-auditor/src
    mkdir -p /app/test_data

    cat << 'EOF' > /app/route-auth-auditor/Cargo.toml
[package]
name = "route-auth-auditor"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /app/route-auth-auditor/src/main.rs
mod decoder;
mod graph;

use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <config.json>", args[0]);
        std::process::exit(1);
    }
    let config_data = std::fs::read_to_string(&args[1]).unwrap();
    let graph = graph::Graph::from_json(&config_data);
    let result = graph.evaluate_node("root");
    println!("Root auth evaluated to: {}", result);
}
EOF

    cat << 'EOF' > /app/route-auth-auditor/src/decoder.rs
pub fn percent_decode(input: &str) -> String {
    // BUG: Needs actual implementation to replace %XX with characters
    input.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_percent_decode() {
        assert_eq!(percent_decode("hello%20world%21"), "hello world!");
        assert_eq!(percent_decode("foo%2Bbar"), "foo+bar");
    }
}
EOF

    cat << 'EOF' > /app/route-auth-auditor/src/graph.rs
use std::collections::HashMap;
use serde::Deserialize;

#[derive(Deserialize)]
struct NodeData {
    base_auth: bool,
    dependencies: Vec<String>,
}

pub struct Graph {
    nodes: HashMap<String, NodeData>,
}

impl Graph {
    pub fn from_json(json: &str) -> Self {
        let nodes: HashMap<String, NodeData> = serde_json::from_str(json).unwrap();
        Graph { nodes }
    }

    // BUG: Unmemoized exponential traversal
    pub fn evaluate_node(&self, node_id: &str) -> bool {
        let node = self.nodes.get(node_id).unwrap();
        let mut allowed = node.base_auth;
        for parent in &node.dependencies {
            allowed = allowed && self.evaluate_node(parent);
        }
        allowed
    }
}
EOF

    python3 -c '
import json
graph = {}
for i in range(50):
    if i == 0:
        graph[f"node_{i}"] = {"base_auth": True, "dependencies": []}
    else:
        graph[f"node_{i}"] = {"base_auth": True, "dependencies": [f"node_{i-1}", f"node_{i-1}"]}
graph["root"] = {"base_auth": True, "dependencies": ["node_49", "node_49"]}
with open("/app/test_data/large_gateway.json", "w") as f:
    json.dump(graph, f)
'

    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
