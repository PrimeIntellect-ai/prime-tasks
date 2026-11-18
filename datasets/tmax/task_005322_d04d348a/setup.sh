#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/lb-operator/src
    cat << 'EOF' > /home/user/lb-operator/Cargo.toml
[package]
name = "lb-operator"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/lb-operator/src/main.rs
// Stub for agent to overwrite
fn main() {}
EOF

    cat << 'EOF' > /home/user/manifest.json
{
  "listen": "127.0.0.1:8888",
  "backends": ["127.0.0.1:9001", "127.0.0.1:9002"]
}
EOF

    cat << 'EOF' > /home/user/run_backends.py
import socket, threading, sys

def handle_client(c, msg):
    try:
        c.sendall(msg.encode())
    except:
        pass
    finally:
        c.close()

def start_server(port, msg):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', port))
    s.listen(5)
    while True:
        c, addr = s.accept()
        threading.Thread(target=handle_client, args=(c, msg)).start()

threading.Thread(target=start_server, args=(9001, "BACKEND_1\n"), daemon=True).start()
threading.Thread(target=start_server, args=(9002, "BACKEND_2\n"), daemon=True).start()

import time
while True:
    time.sleep(1)
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
