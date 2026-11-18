#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create backup manifest
    cat << 'EOF' > /home/user/backup_manifest.json
[
  {"type": "node", "id": "db_primary", "size": 100},
  {"type": "node", "id": "db_replica_1", "size": 50},
  {"type": "node", "id": "db_replica_2", "size": 50},
  {"type": "node", "id": "db_archive", "size": 200},
  {"type": "node", "id": "db_unrelated", "size": 9999},
  {"type": "edge", "source": "db_primary", "target": "db_replica_1"},
  {"type": "edge", "source": "db_primary", "target": "db_replica_2"},
  {"type": "edge", "source": "db_replica_2", "target": "db_archive"}
]
EOF

    # Create Rust project
    cd /home/user
    cargo new backup_graph
    cd backup_graph
    cargo add serde --features derive
    cargo add serde_json

    # Write buggy main.rs
    cat << 'EOF' > src/main.rs
use serde::Deserialize;
use std::fs;

#[derive(Deserialize, Debug)]
#[serde(tag = "type")]
enum ManifestItem {
    #[serde(rename = "node")]
    Node { id: String, size: u64 },
    #[serde(rename = "edge")]
    Edge { source: String, target: String },
}

struct Graph {
    nodes: Vec<(String, u64)>,
    edges: Vec<(String, String)>,
}

fn calculate_chain_size(graph: &Graph, start_node: &str) -> u64 {
    let mut total_size = 0;

    for (id, size) in &graph.nodes {
        if id == start_node {
            total_size += size;
        }
    }

    for (source, target) in &graph.edges {
        for (node_id, _size) in &graph.nodes {
            // BUG: Implicit Cross Join
            // Checking if the edge source is the start_node, but failing to join the target to the node_id!
            if source == start_node {
                // Because there is no `&& node_id == target`, this recurses into `target` for EVERY node in the graph!
                total_size += calculate_chain_size(graph, target);
            }
        }
    }

    total_size
}

fn main() {
    let data = fs::read_to_string("/home/user/backup_manifest.json").unwrap();
    let items: Vec<ManifestItem> = serde_json::from_str(&data).unwrap();

    let mut graph = Graph { nodes: vec![], edges: vec![] };

    for item in items {
        match item {
            ManifestItem::Node { id, size } => graph.nodes.push((id, size)),
            ManifestItem::Edge { source, target } => graph.edges.push((source, target)),
        }
    }

    let size = calculate_chain_size(&graph, "db_primary");
    println!("{}", size);
}
EOF

    chmod -R 777 /home/user
