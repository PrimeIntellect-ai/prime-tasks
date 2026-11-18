#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest websockets pytest-asyncio pwntools

    mkdir -p /home/user/ws_asm
    cd /home/user/ws_asm

    cat << 'EOF' > server.py
import asyncio
import websockets
from pwn import asm, context

context.arch = 'amd64'

async def handler(websocket):
    async for message in websocket:
        try:
            machine_code = asm(message)
            await websocket.send(machine_code.hex())
        except Exception as e:
            await websocket.send("ERROR")

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
EOF

    cat << 'EOF' > test_server.py
import pytest
import asyncio
import websockets
import server

@pytest.fixture
async def ws_server():
    # Broken fixture
    server_task = websockets.serve(server.handler, "localhost", 8765)
    return server_task

@pytest.mark.asyncio
async def test_assembly(ws_server):
    async with websockets.connect("ws://localhost:8765") as ws:
        await ws.send("nop")
        res = await ws.recv()
        assert res == "90"
EOF

    cat << 'EOF' > client.py
import asyncio
import websockets

async def run():
    # TODO: Construct a minimal assembly program that does an exit(42) syscall
    # Connect to ws://localhost:8765, send it, and save the hex response to /home/user/ws_asm/response.log
    pass

if __name__ == "__main__":
    asyncio.run(run())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
