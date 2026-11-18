#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest websockets packaging

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mock_server.py
import asyncio
import websockets
import json
import random

# Fixed seed for deterministic fragmentation
random.seed(42)

UPDATES = [
    {"pkg": "lib-alpha", "old": "1.2.3", "new": "1.3.0"},
    {"pkg": "lib-beta", "old": "2.1.0", "new": "3.0.0"},
    {"pkg": "lib-gamma", "old": "1.1.5", "new": "1.1.4"},
    {"pkg": "lib-delta", "old": "0.9.9", "new": "0.10.0"},
    {"pkg": "lib-epsilon", "old": "4.5.0-alpha", "new": "4.5.0"}
]

async def stream_logs(websocket, path):
    # Serialize updates with some spacing to make state machine parsing necessary
    full_stream = ""
    for update in UPDATES:
        full_stream += json.dumps(update) + "\n"

    # Fragment the stream deterministically
    chunk_size = 5
    i = 0
    while i < len(full_stream):
        size = random.randint(1, chunk_size)
        chunk = full_stream[i:i+size]
        await websocket.send(chunk)
        i += size
        await asyncio.sleep(0.01)

    await websocket.send("EOF")

start_server = websockets.serve(stream_logs, "localhost", 8765)

asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    chmod -R 777 /home/user
