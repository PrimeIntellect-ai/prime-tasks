#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest websockets memory_profiler

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/math_api.py
import asyncio
import websockets

history = []

async def evaluate_math(websocket, path):
    async for message in websocket:
        if message == "SHUTDOWN":
            asyncio.get_event_loop().stop()
            break

        # Memory leak
        history.append(message)

        # Vulnerability
        try:
            result = eval(message)
        except Exception as e:
            result = "ERROR"

        await websocket.send(str(result))

start_server = websockets.serve(evaluate_math, "localhost", 8080)

asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    chmod -R 777 /home/user
