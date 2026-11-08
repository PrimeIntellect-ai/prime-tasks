#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc
    pip3 install pytest websockets

    mkdir -p /home/user

    cat << 'EOF' > /home/user/ws_server.py
import asyncio
import websockets
import os

async def handler(websocket, path):
    async for message in websocket:
        with open("/home/user/ws_out.log", "a") as f:
            f.write(message + "\n")

start_server = websockets.serve(handler, "127.0.0.1", 9000)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    # Start the mock WS server in the background so it's available if tests run in the same session
    python3 /home/user/ws_server.py &
    sleep 2

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
