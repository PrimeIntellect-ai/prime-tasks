#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest websockets

    # Install Rust globally
    export RUSTUP_HOME=/opt/rust/rustup
    export CARGO_HOME=/opt/rust/cargo
    curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable
    chmod -R 777 /opt/rust
    ln -s /opt/rust/cargo/bin/* /usr/local/bin/

    mkdir -p /home/user/ws-eval-proxy/src

    cat << 'EOF' > /home/user/server.py
import asyncio
import websockets
import base64

async def handler(websocket):
    challenges = ["MyArIDQ=", "MTAgKiAy", "MTUgLSA1", "DONE"] # "3 + 4", "10 * 2", "15 - 5"
    expected = ["7", "20", "10"]

    success = True
    for i, chal in enumerate(challenges):
        await websocket.send(chal)
        if chal == "DONE":
            break

        resp = await websocket.recv()
        if resp != expected[i]:
            success = False

    with open("/home/user/results.log", "w") as f:
        if success:
            f.write("SUCCESS: Protocol complete and validated.\n")
        else:
            f.write("FAILURE: Incorrect evaluations.\n")

async def main():
    async with websockets.serve(handler, "127.0.0.1", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

    cat << 'EOF' > /home/user/ws-eval-proxy/Cargo.toml
[package]
name = "ws-eval-proxy"
version = "0.1.0"
edition = "2021"

[dependencies]
tungstenite = "0.20.1"
url = "2.4.1"
base64 = "0.21.5"
EOF

    cat << 'EOF' > /home/user/ws-eval-proxy/src/main.rs
use base64::{engine::general_purpose, Engine as _};
use tungstenite::{connect, Message};
use url::Url;

struct Evaluator {
    last_expr: String,
}

impl Evaluator {
    fn new() -> Self {
        Evaluator { last_expr: String::new() }
    }

    fn evaluate(&mut self, expr: String) -> i32 {
        self.last_expr = expr;

        // Intentional borrow checker error: iterating over a string while trying to use it
        let parts: Vec<&str> = self.last_expr.split_whitespace().collect();

        if parts.len() == 3 {
            let a: i32 = parts[0].parse().unwrap_or(0);
            let b: i32 = parts[2].parse().unwrap_or(0);
            match parts[1] {
                "+" => a + b,
                "-" => a - b,
                "*" => a * b,
                "/" => a / b,
                _ => 0,
            }
        } else {
            0
        }
    }
}

fn main() {
    let (mut socket, _response) = connect(Url::parse("ws://127.0.0.1:8765").unwrap()).expect("Can't connect");
    let mut evaluator = Evaluator::new();

    loop {
        let msg = socket.read().expect("Error reading message");
        if msg.is_text() {
            let text = msg.into_text().unwrap();

            // Intentional ownership error: moving text into decoding, then trying to use it
            let text_moved = text;

            if text_moved == "DONE" {
                break;
            }

            let bytes = general_purpose::STANDARD.decode(text).unwrap(); // ERROR: text used after move
            let expr_str = String::from_utf8(bytes).unwrap();

            let result = evaluator.evaluate(expr_str);

            socket.write(Message::Text(result.to_string())).unwrap();
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
