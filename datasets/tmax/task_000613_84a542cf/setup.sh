#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/ticket_app/src

    # Create memory.dump
    python3 -c "
import os
with open('/home/user/memory.dump', 'wb') as f:
    f.write(os.urandom(1024))
    f.write(b'{\"session\":\"req_8f7b2\",\"user_id\":42,\"data\":\"bad\xffdata\"}')
    f.write(os.urandom(1024))
"

    # Create Cargo.toml
    cat << 'EOF' > /home/user/ticket_app/Cargo.toml
[package]
name = "ticket_app"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = "1.0"
serde_json = "1.0"
EOF

    # Create main.rs
    cat << 'EOF' > /home/user/ticket_app/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
