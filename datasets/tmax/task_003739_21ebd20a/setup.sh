#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest websockets hypothesis

    mkdir -p /home/user/ci_task

    cat << 'EOF' > /home/user/ci_task/raw_payloads.json
[
    {"id": 1, "input": "<script>alert('XSS1');</script>"},
    {"id": 2, "input": "normal data"},
    {"id": 3, "input": "<img src=x onerror=alert(1)>"}
]
EOF

    cat << 'EOF' > /home/user/ci_task/ws_sanitizer.c
#include <stdio.h>

int main() {
    int c;
    while ((c = getchar()) != EOF) {
        if (c == '<') {
            printf("&lt;");
        } else if (c == '>') {
            printf("&gt;");
        } else if (c == 'a') {
            // simplistic sanitization for the word 'alert'
            printf("b");
        } else {
            putchar(c);
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/ci_task/Makefile
ws_sanitizer: ws_sanitizer.c
    gcc -o ws_sanitizer ws_sanitizer.c
EOF

    cat << 'EOF' > /home/user/ci_task/ws_server.py
import asyncio
import websockets
import sys

async def handler(websocket):
    with open(sys.argv[1], 'r') as f:
        data = f.read()
    await websocket.send(data)

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
EOF

    cat << 'EOF' > /home/user/ci_task/pbt_test.py
import asyncio
import websockets
import json
import sys
from hypothesis import given, strategies as st

async def fetch_data():
    try:
        async with websockets.connect("ws://localhost:8765") as ws:
            data = await ws.recv()
            return data
    except Exception as e:
        print(f"Failed to connect to WebSocket: {e}")
        sys.exit(1)

data_str = asyncio.run(fetch_data())
try:
    payloads = json.loads(data_str)
except json.JSONDecodeError:
    print("Invalid JSON structure received.")
    sys.exit(1)

# Property-based testing logic
def verify_properties(data):
    for item in data:
        assert "<" not in item['input'], "Unsanitized '<' found!"
        assert ">" not in item['input'], "Unsanitized '>' found!"
        assert "alert" not in item['input'], "Unsanitized 'alert' found!"

try:
    verify_properties(payloads)
    with open("/home/user/ci_task/success.txt", "w") as f:
        f.write("PBT_PASSED")
    print("All properties passed! Artifact created.")
except AssertionError as e:
    print(f"Property test failed: {e}")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
