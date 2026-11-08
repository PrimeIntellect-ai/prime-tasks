#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv bc
    pip3 install pytest

    mkdir -p /home/user/polybuild

    cat << 'EOF' > /home/user/polybuild/legacy_results.txt
T001,50
T002,25
T003,256
EOF

    python3 -m venv /home/user/polybuild/venv
    /home/user/polybuild/venv/bin/pip install websockets

    cat << 'EOF' > /home/user/polybuild/build_server.py
#!/usr/bin/env python3
import asyncio
import websockets
import sys

async def handler(websocket, path):
    async for message in websocket:
        if message == "GET_TEST_TASKS":
            response = "T001;;45+5*2;;python\nT002;;100/4-5;;nodejs\nT003;;2^8;;cpp"
            await websocket.send(response)
        else:
            await websocket.send("INVALID_COMMAND")

start_server = websockets.serve(handler, "localhost", 9090)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF
    chmod +x /home/user/polybuild/build_server.py

    cat << 'EOF' > /home/user/polybuild/ws_client.py
#!/usr/bin/env python3
import asyncio
import websockets
import sys

async def send_msg():
    uri = "ws://localhost:9090"
    async with websockets.connect(uri) as websocket:
        await websocket.send(sys.argv[1])
        response = await websocket.recv()
        print(response)

asyncio.get_event_loop().run_until_complete(send_msg())
EOF
    chmod +x /home/user/polybuild/ws_client.py

    cat << 'EOF' > /usr/local/bin/python3
#!/bin/bash
if [[ "$1" == *"build_server.py"* || "$1" == *"ws_client.py"* ]]; then
    exec /home/user/polybuild/venv/bin/python3 "$@"
else
    exec /usr/bin/python3 "$@"
fi
EOF
    chmod +x /usr/local/bin/python3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
