#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx iproute2
    pip3 install pytest websockets hypothesis

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/ws_server.py
import asyncio
import websockets
import json
import random

async def handler(websocket):
    count = 0
    while True:
        status = random.choice(["success", "failure", "running"])
        data = {
            "artifact_id": f"build-{count}",
            "status": status,
            "metrics": {
                "size_bytes": random.randint(100, 5000),
                "build_time_sec": round(random.uniform(10.0, 100.0), 2)
            }
        }
        await websocket.send(json.dumps(data))
        count += 1
        await asyncio.sleep(0.1)

async def main():
    async with websockets.serve(handler, "127.0.0.1", 8080):
        await asyncio.Future()

asyncio.run(main())
EOF

    chmod -R 777 /home/user
