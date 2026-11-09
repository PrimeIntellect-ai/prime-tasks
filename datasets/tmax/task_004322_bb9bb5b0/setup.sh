#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.json
{"id": 42, "event": "migration_test"}
EOF

    cat << 'EOF' > /home/user/echo_server.py
import asyncio
import websockets

async def echo(websocket, path):
    async for message in websocket:
        await websocket.send(message)

start_server = websockets.serve(echo, "localhost", 8765)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    cat << 'EOF' > /home/user/ws_processor.py
import json
import zlib
import asyncio
import websockets

async def process():
    with open('/home/user/data.json', 'r') as f:
        data = json.load(f)

    # Sort keys for deterministic serialization
    payload = json.dumps(data, sort_keys=True)

    # INTENTIONAL BUG: zlib.crc32 needs bytes in Py3, but payload is a string
    checksum = zlib.crc32(payload)

    message = json.dumps({"payload": payload, "checksum": checksum})

    async with websockets.connect("ws://localhost:8765") as websocket:
        await websocket.send(message)
        response = await websocket.recv()

    with open('/home/user/success.log', 'w') as f:
        f.write(response)

asyncio.get_event_loop().run_until_complete(process())
EOF

    chmod -R 777 /home/user
