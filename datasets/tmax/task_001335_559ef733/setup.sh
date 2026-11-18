#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    python3 -c '
import os
import json

os.makedirs("/app/vendored/graph-mapper/src", exist_ok=True)
os.makedirs("/app/data/clean_corpus", exist_ok=True)
os.makedirs("/app/data/evil_corpus", exist_ok=True)

cargo_toml = """[package]
name = "graph-mapper"
version = "0.2.1"
edition = "2021"

[dependencies]
# serde is missing!
"""
with open("/app/vendored/graph-mapper/Cargo.toml", "w") as f:
    f.write(cargo_toml)

lib_rs = """
use std::collections::{HashMap, HashSet};

pub struct Graph {
    pub nodes: HashSet<String>,
    pub edges: HashMap<String, Vec<String>>,
}

impl Graph {
    pub fn new() -> Self {
        Graph {
            nodes: HashSet::new(),
            edges: HashMap::new(),
        }
    }
    pub fn add_node(&mut self, id: String) {
        self.nodes.insert(id);
    }
    pub fn add_edge(&mut self, from: String, to: String) {
        self.edges.entry(from).or_default().push(to);
    }
    pub fn has_cycle(&self) -> bool {
        let mut visited = HashSet::new();
        let mut rec_stack = HashSet::new();
        for node in &self.nodes {
            if self.is_cyclic_util(node, &mut visited, &mut rec_stack) {
                return true;
            }
        }
        false
    }
    fn is_cyclic_util(&self, v: &String, visited: &mut HashSet<String>, rec_stack: &mut HashSet<String>) -> bool {
        if !visited.contains(v) {
            visited.insert(v.clone());
            rec_stack.insert(v.clone());
            if let Some(neighbors) = self.edges.get(v) {
                for neighbor in neighbors {
                    if !visited.contains(neighbor) && self.is_cyclic_util(neighbor, visited, rec_stack) {
                        return true;
                    } else if rec_stack.contains(neighbor) {
                        return true;
                    }
                }
            }
        }
        rec_stack.remove(v);
        false
    }
    pub fn has_path(&self, start: &String, end: &String) -> bool {
        let mut visited = HashSet::new();
        let mut queue = vec![start.clone()];
        visited.insert(start.clone());
        while let Some(node) = queue.pop() {
            if &node == end {
                return true;
            }
            if let Some(neighbors) = self.edges.get(&node) {
                for neighbor in neighbors {
                    if !visited.contains(neighbor) {
                        visited.insert(neighbor.clone());
                        queue.push(neighbor.clone());
                    }
                }
            }
        }
        false
    }
}
"""
with open("/app/vendored/graph-mapper/src/lib.rs", "w") as f:
    f.write(lib_rs)

clean_data = {
    "document": {
        "doc_id": "doc1",
        "dataset_refs": ["ds1", "ds2"]
    },
    "graph": {
        "nodes": [
            {"id": "doc1", "type": "Document"},
            {"id": "ds1", "type": "Dataset"},
            {"id": "ds2", "type": "Dataset"}
        ],
        "edges": [
            {"source": "doc1", "target": "ds1", "relation": "uses"},
            {"source": "doc1", "target": "ds2", "relation": "uses"}
        ]
    }
}
with open("/app/data/clean_corpus/clean1.json", "w") as f:
    json.dump(clean_data, f)

evil_data = {
    "document": {
        "doc_id": "doc1",
        "dataset_refs": ["ds1"]
    },
    "graph": {
        "nodes": [
            {"id": "doc1", "type": "Document"},
            {"id": "ds1", "type": "Dataset"}
        ],
        "edges": [
            {"source": "doc1", "target": "ds1", "relation": "uses"},
            {"source": "ds1", "target": "doc1", "relation": "cycle"}
        ]
    }
}
with open("/app/data/evil_corpus/evil1.json", "w") as f:
    json.dump(evil_data, f)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
