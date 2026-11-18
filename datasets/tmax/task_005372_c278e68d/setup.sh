#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest websockets packaging

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/endpoints.csv
endpoint,min_version
ws://localhost:9001,1.2.0
ws://localhost:9002,2.0.0
ws://localhost:9003,1.5.5
EOF

    cat << 'EOF' > /home/user/server.py
import asyncio
import websockets
import json

async def handler_9001(websocket, path=""):
    async for message in websocket:
        data = json.loads(message)
        if data.get("cmd") == "version":
            await websocket.send(json.dumps({"version": "1.1.9"}))
        elif data.get("cmd") == "test":
            await websocket.send(json.dumps({"status": "ok"}))

async def handler_9002(websocket, path=""):
    async for message in websocket:
        data = json.loads(message)
        if data.get("cmd") == "version":
            await websocket.send(json.dumps({"version": "2.1.0"}))
        elif data.get("cmd") == "test":
            if data.get("auth") == "e2e-token":
                await websocket.send(json.dumps({"status": "ok"}))
            else:
                await websocket.send(json.dumps({"status": "error"}))

async def handler_9003(websocket, path=""):
    async for message in websocket:
        data = json.loads(message)
        if data.get("cmd") == "version":
            await websocket.send(json.dumps({"version": "1.5.5"}))
        elif data.get("cmd") == "test":
            await websocket.send(json.dumps({"status": "error"}))

async def main():
    server1 = await websockets.serve(handler_9001, "localhost", 9001)
    server2 = await websockets.serve(handler_9002, "localhost", 9002)
    server3 = await websockets.serve(handler_9003, "localhost", 9003)
    await asyncio.gather(server1.wait_closed(), server2.wait_closed(), server3.wait_closed())

if __name__ == "__main__":
    asyncio.run(main())
EOF

    chmod -R 777 /home/user
