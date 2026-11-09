#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl time patch
pip3 install pytest websockets

export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
export PATH="/usr/local/cargo/bin:${PATH}"
chmod -R 777 /usr/local/cargo /usr/local/rustup

mkdir -p /home/user/ws_server/src

cat << 'EOF' > /home/user/ws_server/Cargo.toml
[package]
name = "ws_server"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.0", features = ["full"] }
tokio-tungstenite = "0.20"
futures-util = "0.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

cat << 'EOF' > /home/user/ws_server/src/main.rs
use tokio::net::TcpListener;
use tokio_tungstenite::accept_async;
use futures_util::{StreamExt, SinkExt};

#[tokio::main]
async fn main() {
    let listener = TcpListener::bind("127.0.0.1:8080").await.unwrap();
    while let Ok((stream, _)) = listener.accept().await {
        tokio::spawn(async move {
            let mut ws_stream = accept_async(stream).await.expect("Failed to accept");
            while let Some(msg) = ws_stream.next().await {
                let msg = msg.unwrap();
                ws_stream.send(msg).await.unwrap();
            }
        });
    }
}
EOF

cat << 'EOF' > /home/user/feature.patch
--- src/main.rs
+++ src/main.rs
@@ -1,15 +1,38 @@
 use tokio::net::TcpListener;
 use tokio_tungstenite::accept_async;
+use tokio_tungstenite::tungstenite::Message;
 use futures_util::{StreamExt, SinkExt};
+use serde::{Deserialize, Serialize};
+use std::sync::Arc;
+
+#[derive(Deserialize)]
+struct Request {
+    action: String,
+    data: Vec<i32>,
+}
+
+#[derive(Serialize)]
+struct Response {
+    status: String,
+    sum: i32,
+}

 #[tokio::main]
 async fn main() {
     let listener = TcpListener::bind("127.0.0.1:8080").await.unwrap();
+    let server_name = String::from("RustTestServer");
+
     while let Ok((stream, _)) = listener.accept().await {
         tokio::spawn(async move {
             let mut ws_stream = accept_async(stream).await.expect("Failed to accept");
             while let Some(msg) = ws_stream.next().await {
                 let msg = msg.unwrap();
-                ws_stream.send(msg).await.unwrap();
+                if msg.is_text() {
+                    let req: Request = serde_json::from_str(msg.to_text().unwrap()).unwrap();
+                    if req.action == "shutdown" { std::process::exit(0); }
+                    let res = Response { status: server_name, sum: req.data.iter().sum() };
+                    let res_text = serde_json::to_string(&res).unwrap();
+                    ws_stream.send(Message::Text(res_text)).await.unwrap();
+                }
             }
         });
     }
 }
EOF

cat << 'EOF' > /home/user/test_client.py
import asyncio
import websockets
import json

async def test():
    async with websockets.connect("ws://127.0.0.1:8080") as ws:
        await ws.send(json.dumps({"action": "process", "data": [10, 20, 30]}))
        resp = await ws.recv()
        data = json.loads(resp)
        assert data["sum"] == 60

        with open("/home/user/test_results.json", "w") as f:
            json.dump({"success": True}, f)

asyncio.run(test())
EOF

cat << 'EOF' > /home/user/load_test.py
import asyncio
import websockets
import json

async def load():
    async with websockets.connect("ws://127.0.0.1:8080") as ws:
        for _ in range(100):
            await ws.send(json.dumps({"action": "process", "data": [1, 1, 1]}))
            await ws.recv()
        await ws.send(json.dumps({"action": "shutdown", "data": []}))

asyncio.run(load())
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
