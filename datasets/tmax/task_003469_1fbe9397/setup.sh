#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc curl rustc cargo
    pip3 install pytest

    mkdir -p /app/router_gen/src

    cat << 'EOF' > /app/routes.json
{"exec_route": "/api/exec"}
EOF

    cat << 'EOF' > /app/router_gen/Cargo.toml
[package]
name = "router_gen"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/router_gen/src/main.rs
use std::fs;

fn parse_route<'a>(content: &str) -> &'a str {
    let s = String::from("/api/exec");
    &s
}

fn main() {
    let content = fs::read_to_string("/app/routes.json").unwrap();
    let route = parse_route(&content);
    println!("#define EXEC_ROUTE \"{}\"", route);
}
EOF

    ffmpeg -f lavfi -i color=c=red:s=100x100:d=1 \
           -f lavfi -i color=c=red:s=100x100:d=1 \
           -f lavfi -i color=c=blue:s=100x100:d=1 \
           -f lavfi -i color=c=green:s=100x100:d=1 \
           -f lavfi -i color=c=white:s=100x100:d=1 \
           -filter_complex "[0:v][1:v][2:v][3:v][4:v]concat=n=5:v=1:a=0[outv]" \
           -map "[outv]" -c:v libx264 -pix_fmt yuv420p /app/signal.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
