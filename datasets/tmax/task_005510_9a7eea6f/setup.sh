#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc socat
    pip3 install pytest websockets

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/py2_evaluator/src

    cat << 'EOF' > /home/user/py2_evaluator/Cargo.toml
[package]
name = "py2_evaluator"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.28", features = ["full"] }
tokio-tungstenite = "0.19"
futures-util = "0.3"
EOF

    cat << 'EOF' > /home/user/py2_evaluator/src/main.rs
fn main() {}
EOF

    cat << 'EOF' > /home/user/benchmark.sh
#!/bin/bash
# A script to run the benchmark against the WS proxy.
cat << 'INNER_EOF' > /home/user/client.py
import asyncio
import websockets
import time
import sys

async def test():
    uri = "ws://127.0.0.1:8080"
    tests = ['print "hello"', '5 / 2', 'print 7 / 2', 'invalid']
    try:
        async with websockets.connect(uri) as websocket:
            for t in tests:
                start = time.time()
                await websocket.send(t)
                res = await websocket.recv()
                end = time.time()
                latency = int((end - start) * 1000)
                print(f"{latency} {res}")
    except Exception as e:
        print(f"Failed: {e}")
        sys.exit(1)

asyncio.run(test())
INNER_EOF
python3 /home/user/client.py > /home/user/raw_results.txt
EOF

    chmod +x /home/user/benchmark.sh

    chmod -R 777 /home/user
