#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.js | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /app/recovery_api/src
    mkdir -p /app/recovery_api/exports

    # 1. Python storage backend
    cat << 'EOF' > /app/storage_backend.py
import http.server
import socketserver

PORT = 9000
Handler = http.server.SimpleHTTPRequestHandler
with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    # 2. Dummy ELF malware implant
    cat << 'EOF' > /tmp/malware.c
#include <stdio.h>
const char key[] __attribute__((section(".rodata"))) = "a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e";
int main() {
    printf("Malware running...\n");
    return 0;
}
EOF
    gcc /tmp/malware.c -o /app/malware_implant.bin
    rm /tmp/malware.c

    # 3. Rust recovery API
    cat << 'EOF' > /app/recovery_api/Cargo.toml
[package]
name = "recovery_api"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
EOF

    cat << 'EOF' > /app/recovery_api/src/main.rs
fn main() {
    println!("Recovery API");
}
EOF

    cat << 'EOF' > /app/recovery_api/.env
STORAGE_URL=http://127.0.0.1:9999
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
