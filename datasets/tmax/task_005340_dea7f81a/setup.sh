#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /app/ws-route-parser/src

    cat << 'EOF' > /app/ws-route-parser/Cargo.toml
[package]
name = "ws-route-parser"
version = "1.0.0"
edition = "2021"
EOF

    cat << 'EOF' > /app/ws-route-parser/src/main.rs
use std::env;

fn extract_path(url: &str) -> &str {
    let decoded = url.replace("%20", " ");
    let path = decoded.split('?').next().unwrap_or("");
    path // ERROR: returning reference to local variable `decoded`
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { return; }
    let url = &args[1];

    // Broken usage
    let path = extract_path(url);
    print!("PATH={} ", path);

    if let Some(query) = url.split('?').nth(1) {
        for pair in query.split('&') {
            let mut parts = pair.split('=');
            if let (Some(k), Some(v)) = (parts.next(), parts.next()) {
                print!("{}={} ", k.to_uppercase(), v);
            }
        }
    }
    println!();
}
EOF

    mkdir -p /app/corpus/clean /app/corpus/evil

    echo -n "/api/stream?room=42" > /app/corpus/clean/clean1.txt
    echo -n "/ws/chat" > /app/corpus/clean/clean2.txt
    echo -n "/api/admin/settings?token=abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789" > /app/corpus/clean/clean3.txt
    echo -n "/api/normal?token=short" > /app/corpus/clean/clean4.txt

    echo -n "/api/stream?room=1001" > /app/corpus/evil/evil1.txt
    echo -n "/api/../etc/passwd" > /app/corpus/evil/evil2.txt
    echo -n "/api/admin/settings?token=short" > /app/corpus/evil/evil3.txt
    echo -n "/bad/path" > /app/corpus/evil/evil4.txt
    echo -n "/ws/admin_panel" > /app/corpus/evil/evil5.txt
    echo -n "/api/stream?room=0" > /app/corpus/evil/evil6.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
