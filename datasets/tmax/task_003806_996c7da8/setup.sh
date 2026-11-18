#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cargo build-essential
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create data directories
    mkdir -p /home/user/data

    # Create nodes.csv
    cat << 'EOF' > /home/user/data/nodes.csv
id,name,type
root,Root Node,start
child1,Child 1,mid
child2,Child 2,mid
child3,Child 3,end
EOF

    # Create edges.csv
    cat << 'EOF' > /home/user/data/edges.csv
parent_id,child_id,weight
root,child1,100
child1,child2,150
child2,child3,200
EOF

    # Create vendored graph engine
    mkdir -p /app/vendored/graph-engine-0.4.2/src

    cat << 'EOF' > /app/vendored/graph-engine-0.4.2/Cargo.toml
[package]
name = "graph-engine"
version = "0.4.2"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/vendored/graph-engine-0.4.2/src/lib.rs
pub mod recursion;
EOF

    cat << 'EOF' > /app/vendored/graph-engine-0.4.2/src/recursion.rs
pub fn execute_recursive(depth: u32) {
    if depth > 1 { panic!("Max depth exceeded in dev mode"); }
}
EOF

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
