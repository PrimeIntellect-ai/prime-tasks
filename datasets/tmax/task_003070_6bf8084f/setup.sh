#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/gateway/payload_filter/src \
             /home/user/gateway/gateway_server/src \
             /home/user/gateway/config \
             /home/user/corpora/clean \
             /home/user/corpora/evil \
             /home/user/deploy/releases \
             /home/user/deploy/backups

    echo '{"name": "test", "value": 123}' > /home/user/corpora/clean/1.json
    echo '{"data": {"nested": "valid"}}' > /home/user/corpora/clean/2.json
    echo '{"__proto__": {"admin": true}}' > /home/user/corpora/evil/1.json
    echo '{"user": "test", "bio": "hello <script>alert(1)</script>"}' > /home/user/corpora/evil/2.json

    cat << 'EOF' > /home/user/gateway/config/settings.toml
bind_port = 8080
upstream_port = 8082
EOF

    cat << 'EOF' > /home/user/gateway/Cargo.toml
[workspace]
members = [
    "payload_filter",
    "gateway_server"
]
EOF

    cat << 'EOF' > /home/user/gateway/payload_filter/Cargo.toml
[package]
name = "payload_filter"
version = "0.1.0"
edition = "2021"

[dependencies]
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/gateway/payload_filter/src/main.rs
fn main() {
    // TODO: implement payload filter
}
EOF

    cat << 'EOF' > /home/user/gateway/gateway_server/Cargo.toml
[package]
name = "gateway_server"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/gateway/gateway_server/src/main.rs
use std::env;
use std::fs;
use std::net::{TcpListener, TcpStream};
use std::io::{Read, Write};

fn main() {
    let config = fs::read_to_string("/home/user/gateway/config/settings.toml").unwrap();
    let mut bind_port = "8080";
    let mut upstream_port = "8082";
    for line in config.lines() {
        if line.starts_with("bind_port") {
            bind_port = line.split('=').nth(1).unwrap().trim();
        }
        if line.starts_with("upstream_port") {
            upstream_port = line.split('=').nth(1).unwrap().trim();
        }
    }

    let listener = TcpListener::bind(format!("127.0.0.1:{}", bind_port)).unwrap();
    for stream in listener.incoming() {
        let mut client = stream.unwrap();
        let mut buffer = [0; 1024];
        client.read(&mut buffer).unwrap();

        if let Ok(mut server) = TcpStream::connect(format!("127.0.0.1:{}", upstream_port)) {
            server.write_all(&buffer).unwrap();
            let mut server_buf = Vec::new();
            server.read_to_end(&mut server_buf).unwrap_or(0);
            client.write_all(&server_buf).unwrap();
        } else {
            client.write_all(b"HTTP/1.1 502 Bad Gateway\r\n\r\n").unwrap();
        }
    }
}
EOF

    chmod -R 777 /home/user
