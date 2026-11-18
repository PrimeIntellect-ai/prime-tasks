#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo
pip3 install pytest

# Create directories
mkdir -p /app/rbac_engine-0.1.0/src
mkdir -p /app/schema
mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil

# Create Rust project files
cat << 'EOF' > /app/rbac_engine-0.1.0/Cargo.toml
[package]
name = "rbac-cli"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /app/rbac_engine-0.1.0/src/main.rs
fn main() {
    let strict = option_env!("RBAC_GRAPH_STRICT").unwrap_or("0");
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        std::process::exit(1);
    }
    let req_content = std::fs::read_to_string(&args[2]).unwrap_or_default();
    if req_content.contains("evil") {
        if strict == "1" {
            println!("DENY");
        } else {
            println!("ALLOW");
        }
    } else {
        println!("ALLOW");
    }
}
EOF

# Create Makefile with spaces instead of tabs and RBAC_GRAPH_STRICT=0
cat << 'EOF' > /app/rbac_engine-0.1.0/Makefile
build:
    export RBAC_GRAPH_STRICT=0; cargo build --release
EOF

# Create schema
cat << 'EOF' > /app/schema/system_graph.yaml
nodes:
  - id: user1
  - id: resource1
edges:
  - from: user1
    to: resource1
EOF

# Create clean and evil corpora
cat << 'EOF' > /app/corpora/clean/req_01.json
{
  "user": "user1",
  "resource": "resource1",
  "type": "clean"
}
EOF

cat << 'EOF' > /app/corpora/evil/req_01.json
{
  "user": "user2",
  "resource": "resource1",
  "type": "evil"
}
EOF

# Create user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
