#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo espeak-ng ffmpeg curl
pip3 install pytest

# Create directories
mkdir -p /home/user/artifact_manager/src
mkdir -p /app/artifacts

# Generate audio file
espeak-ng -w /app/artifacts/release_notes_v2.wav "Fixed the concurrent modification bug in the build cache and upgraded the networking library to version two point one."

# Create Rust project files
cat << 'EOF' > /home/user/artifact_manager/Cargo.toml
[package]
name = "artifact_manager"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

cat << 'EOF' > /home/user/artifact_manager/src/main.rs
mod graph;
use graph::Graph;
use std::fs;

fn main() {
    let data = fs::read_to_string("artifacts_graph.json").unwrap();
    let mut g = Graph::new();
    g.load(&data);
    let sorted = g.topological_sort();
    // Finish implementation here
}
EOF

cat << 'EOF' > /home/user/artifact_manager/src/graph.rs
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Debug)]
pub struct Artifact {
    pub id: String,
    pub r#type: String,
    pub dependencies: Vec<String>,
}

pub struct Graph {
    nodes: Vec<Artifact>,
}

impl Graph {
    pub fn new() -> Self {
        Graph { nodes: Vec::new() }
    }

    pub fn load(&mut self, data: &str) {
        let artifacts: Vec<Artifact> = serde_json::from_str(data).unwrap();
        // Intentional borrow checker issue
        let r = &artifacts[0];
        self.nodes = artifacts;
        println!("Loaded: {}", r.id);
    }

    pub fn topological_sort(&self) -> Vec<&Artifact> {
        // Dummy incomplete implementation
        self.nodes.iter().collect()
    }
}
EOF

cat << 'EOF' > /home/user/artifact_manager/artifacts_graph.json
[
  {
    "id": "base_lib",
    "type": "binary",
    "dependencies": []
  },
  {
    "id": "release_notes",
    "type": "audio_memo",
    "dependencies": ["base_lib"]
  }
]
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/artifact_manager
chmod -R 777 /home/user
chmod -R 777 /app
