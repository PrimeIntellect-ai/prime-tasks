#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/app/src
    mkdir -p /home/user/app/specs

    cat << 'EOF' > /home/user/app/Cargo.toml
[package]
name = "api_gateway"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/app/src/main.rs
mod limits;

fn main() {
    let limit = limits::get_limit("/api/v1/users");
    println!("Limit: {:?}", limit);
}
EOF

    cat << 'EOF' > /home/user/app/specs/api_v1.json
{
    "/api/v1/users": 100,
    "/api/v1/posts": 50,
    "/api/v1/admin": 10
}
EOF

    cat << 'EOF' > /home/user/app/specs/api_v2.json
{
    "/api/v2/comments": 200,
    "/api/v1/users": 80,
    "/api/v2/tags": 500
}
EOF

    cat << 'EOF' > /home/user/app/specs/api_v3.json
{
    "/api/v1/admin": 5,
    "/api/v3/status": 1000,
    "/api/v2/comments": 250
}
EOF

    cat << 'EOF' > /home/user/app/specs/old_limits.rs
pub fn get_limit(path: &str) -> Option<u32> {
    match path {
        "/api/v1/users" => Some(100),
        "/api/v1/posts" => Some(50),
        "/api/v1/admin" => Some(10),
        _ => None,
    }
}
EOF

    cat << 'EOF' > /home/user/app/generate_limits.py
import json
import glob
import os

def merge_specs(spec_files):
    merged = []
    for f in spec_files:
        with open(f) as fp:
            merged.extend(json.load(fp).items())
    return merged

def generate_rust(merged_data, output_file):
    with open(output_file, 'w') as f:
        f.write("pub fn get_limit(path: &str) -> Option<u32> {\n")
        f.write("    match path {\n")
        for path, limit in merged_data:
            f.write(f'        "{path}" => Some({limit}),\n')
        f.write("        _ => None,\n")
        f.write("    }\n")
        f.write("}\n")

if __name__ == "__main__":
    files = glob.glob("specs/*.json")
    data = merge_specs(files)
    generate_rust(data, "src/limits.rs")
EOF

    cd /home/user/app
    python3 generate_limits.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
