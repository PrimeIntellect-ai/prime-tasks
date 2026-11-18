#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/graph_exporter/src

    cat << 'EOF' > /home/user/data/authors.csv
author_id,name
1,Alice
2,Bob
3,Charlie
EOF

    cat << 'EOF' > /home/user/data/papers.csv
paper_id,title
101,Graph Databases in Practice
102,Rust for Data Engineering
103,Implicit Cross Joins and How to Avoid Them
EOF

    cat << 'EOF' > /home/user/data/authors_papers.csv
author_id,paper_id
1,101
1,102
2,102
3,103
EOF

    cat << 'EOF' > /home/user/graph_exporter/Cargo.toml
[package]
name = "graph_exporter"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.1"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/graph_exporter/src/main.rs
use std::fs::File;
use std::io::Write;

fn main() {
    // BUGGY SCRIPT: Creates an implicit cross join
    let authors = vec![1, 2, 3];
    let papers = vec![101, 102, 103];

    let mut file = File::create("/home/user/graph_exporter/output.cypher").unwrap();

    for a in &authors {
        for p in &papers {
EOF
    echo -e "            writeln!(file, \"MERGE (a:Author \x7B\x7Bid: {}\x7D\x7D) MERGE (p:Paper \x7B\x7Bid: {}\x7D\x7D) MERGE (a)-[:WROTE]->(p);\", a, p).unwrap();" >> /home/user/graph_exporter/src/main.rs
    cat << 'EOF' >> /home/user/graph_exporter/src/main.rs
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
