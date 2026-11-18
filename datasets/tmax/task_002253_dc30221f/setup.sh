#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo build-essential
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/graph_oracle.rs
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::File;
use std::io::{self, BufRead, BufReader};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        std::process::exit(1);
    }

    let mut nodes: HashMap<String, i64> = HashMap::new();
    if let Ok(file) = File::open(&args[1]) {
        for line in BufReader::new(file).lines().flatten() {
            let parts: Vec<&str> = line.split(',').collect();
            if parts.len() >= 2 {
                if let Ok(w) = parts[1].parse::<i64>() {
                    nodes.insert(parts[0].to_string(), w);
                }
            }
        }
    }

    let mut edges: HashMap<String, Vec<(String, String)>> = HashMap::new();
    if let Ok(file) = File::open(&args[2]) {
        for line in BufReader::new(file).lines().flatten() {
            let parts: Vec<&str> = line.split(',').collect();
            if parts.len() >= 3 {
                edges.entry(parts[0].to_string())
                    .or_default()
                    .push((parts[2].to_string(), parts[1].to_string()));
            }
        }
    }

    let stdin = io::stdin();
    for line in stdin.lock().lines().flatten() {
        if line.trim().is_empty() {
            continue;
        }
        let parts: Vec<&str> = line.trim().split(',').collect();
        let start_node = parts[0].to_string();
        let mut current_nodes: HashSet<String> = HashSet::new();
        current_nodes.insert(start_node);

        for edge_type in parts.iter().skip(1) {
            let mut next_nodes: HashSet<String> = HashSet::new();
            for node in current_nodes {
                if let Some(node_edges) = edges.get(&node) {
                    for (etype, target) in node_edges {
                        if etype == edge_type {
                            next_nodes.insert(target.clone());
                        }
                    }
                }
            }
            current_nodes = next_nodes;
        }

        let mut sum: i64 = 0;
        for node in current_nodes {
            if let Some(&w) = nodes.get(&node) {
                sum += w;
            }
        }
        println!("RESULT: {}", sum);
    }
}
EOF

    rustc -O /tmp/graph_oracle.rs -o /app/graph_oracle
    strip /app/graph_oracle
    rm /tmp/graph_oracle.rs

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/sample_data

    cat << 'EOF' > /home/user/sample_data/nodes.csv
A,10
B,20
C,30
D,40
E,50
EOF

    cat << 'EOF' > /home/user/sample_data/edges.csv
A,B,KNOWS
B,C,LIKES
C,D,FOLLOWS
D,E,BLOCKS
A,E,TRUSTS
EOF

    chmod -R 777 /home/user
