#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc curl
    pip3 install pytest

    mkdir -p /app/vendored/dataset_graph/src
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/graph_schema.json
{
  "nodes": ["A", "B", "C", "D", "E", "F", "G"],
  "edges": [["A", "B"], ["B", "C"], ["C", "D"], ["D", "E"], ["E", "F"], ["A", "G"]]
}
EOF

    cat << 'EOF' > /app/vendored/dataset_graph/Cargo.toml
[package]
name = "dataset_graph"
version = "0.1.0"
edition = 2021 # ERROR: missing quotes

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /app/vendored/dataset_graph/src/lib.rs
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, VecDeque};

#[derive(Serialize, Deserialize, Debug)]
pub struct Graph {
    pub nodes: Vec<String>,
    pub edges: Vec<[String; 2]>,
}

impl Graph {
    pub fn from_json(json: &str) -> Self {
        serde_json::from_str(json).unwrap()
    }

    pub fn shortest_path(&self, source: &str, target: &str) -> Option<usize> {
        let mut adj: HashMap<&str, Vec<&str>> = HashMap::new();
        for node in &self.nodes {
            adj.insert(node.as_str(), Vec::new());
        }
        for edge in &self.edges {
            if let [u, v] = edge.as_slice() {
                adj.entry(u).or_default().push(v);
                adj.entry(v).or_default().push(u);
            }
        }

        if !adj.contains_key(source) || !adj.contains_key(target) {
            return None;
        }

        let mut queue = VecDeque::new();
        let mut visited = HashSet::new();

        queue.push_back((source, 0));
        visited.insert(source);

        while let Some((curr, dist)) = queue.pop_front() {
            if curr == target {
                return Some(dist);
            }

            if let Some(neighbors) = adj.get(curr) {
                for &neighbor in neighbors {
                    if !visited.contains(neighbor) {
                        visited.insert(neighbor);
                        queue.push_back((neighbor, dist + 1));
                    }
                }
            }
        }
        None
    }
}
EOF

    cat << 'EOF' > /app/corpus/clean/clean_1.json
{
  "experiment_id": "EXP-001",
  "timestamp": "2023-10-01T12:00:00Z",
  "source_node": "A",
  "target_node": "C",
  "metrics": {}
}
EOF

    cat << 'EOF' > /app/corpus/evil/evil_1.json
{
  "experiment_id": "EXP-E1",
  "timestamp": "2023-10-01T12:00:00Z",
  "source_node": "A",
  "target_node": "F",
  "metrics": {}
}
EOF

    cat << 'EOF' > /app/corpus/evil/evil_2.json
{
  "timestamp": "2023-10-01T12:00:00Z",
  "source_node": "A",
  "target_node": "C",
  "metrics": {}
}
EOF

    cat << 'EOF' > /app/corpus/evil/evil_3.json
{
  "experiment_id": "EXP-E3",
  "timestamp": "2025-10-01T12:00:00Z",
  "source_node": "A",
  "target_node": "C",
  "metrics": {}
}
EOF

    cat << 'EOF' > /app/corpus/evil/evil_4.json
{
  "experiment_id": "EXP-E4",
  "timestamp": "2023-10-01T12:00:00Z",
  "source_node": "A",
  "target_node": "Z",
  "metrics": {}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
