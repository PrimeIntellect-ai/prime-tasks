#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/cities.csv
id,name
1,Graphville
2,SQLton
EOF

    cat << 'EOF' > /home/user/data/users.csv
id,name,city_id
1,Alice,1
2,Bob,2
3,Charlie,1
4,Dave,1
5,Eve,2
EOF

    cat << 'EOF' > /home/user/data/friendships.csv
user1_id,user2_id
1,2
2,3
3,4
1,5
EOF

    mkdir -p /home/user/graph_builder/src
    cat << 'EOF' > /home/user/graph_builder/Cargo.toml
[package]
name = "graph_builder"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.1"
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > /home/user/graph_builder/src/main.rs
fn main() {
    println!("Please implement the CSV to Cypher generator.");
}
EOF

    chmod -R 777 /home/user
