#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest websockets

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create directory
    mkdir -p /home/user/math_feature

    # Create server.rs
    cat << 'EOF' > /home/user/math_feature/server.rs
use std::net::TcpListener;
use std::thread::spawn;
use tungstenite::server::accept;
use serde_json::Value;

fn main() {
    let server = TcpListener::bind("127.0.0.1:8765").unwrap();
    for stream in server.incoming() {
        spawn(move || {
            let mut websocket = accept(stream.unwrap()).unwrap();

            let status_msg = String::from("connected");
            let _moved_msg = status_msg;
            // BORROW CHECKER ERROR HERE
            println!("Connection status: {}", status_msg); 

            loop {
                let msg = websocket.read().unwrap();
                if msg.is_text() {
                    let parsed: Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
                    let arr = parsed["data"].as_array().unwrap();
                    let mut sum = 0;
                    for num in arr {
                        let val = num.as_i64().unwrap();
                        sum += val * val;
                    }
                    websocket.write(tungstenite::Message::Text(sum.to_string())).unwrap();
                }
            }
        });
    }
}
EOF

    # Create test_e2e.py
    cat << 'EOF' > /home/user/math_feature/test_e2e.py
import asyncio
import websockets
import json

async def test_math_server():
    uri = "ws://127.0.0.1:8765"
    async with websockets.connect(uri) as websocket:
        payload = {"data": [2, 4, 6, 8]}
        # BUG: Sending dict instead of json string
        await websocket.send(payload)

        response = await websocket.recv()
        result = int(response)

        with open("/home/user/math_success.log", "w") as f:
            f.write(f"RESULT: {result}\n")

asyncio.run(test_math_server())
EOF

    # Setup a Cargo project so that crates are available if the agent decides to use Cargo
    cd /home/user/math_feature
    cargo init --name math_server --bin || true
    cat << 'EOF' > Cargo.toml
[package]
name = "math_server"
version = "0.1.0"
edition = "2021"

[dependencies]
tungstenite = "0.20.1"
serde_json = "1.0"
EOF
    # Symlink server.rs to src/main.rs so cargo build works if they figure it out
    rm -f src/main.rs
    ln -s ../server.rs src/main.rs

    # Ensure permissions
    chmod -R 777 /home/user
