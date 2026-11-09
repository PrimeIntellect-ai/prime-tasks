#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest websockets

    mkdir -p /home/user/libs
    touch /home/user/libs/libcore.so.0.9.0
    touch /home/user/libs/libcore.so.1.0.5
    touch /home/user/libs/libcore.so.1.2.0
    touch /home/user/libs/libcore.so.2.0.1
    touch /home/user/libs/libnet.so.1.2.0
    touch /home/user/libs/libnet.so.1.2.4
    touch /home/user/libs/libnet.so.1.3.0
    touch /home/user/libs/libnet.so.2.0.0
    touch /home/user/libs/libmath.so.2.9.9
    touch /home/user/libs/libmath.so.3.0.1
    touch /home/user/libs/libmath.so.3.1.4
    touch /home/user/libs/libmath.so.3.2.0

    cat << 'EOF' > /home/user/build_server.py
import asyncio
import websockets
import time

async def stream_logs(websocket, path):
    logs = [
        "[START BUILD] app_server",
        "[ANALYZE] net_module",
        "[DEPENDENCY] libnet >= 1.2.0 AND libnet < 2.0.0",
        "[ANALYZE] core_module",
        "[DEPENDENCY] libcore >= 1.0.0 AND libcore < 2.0.0",
        "[DEPENDENCY] libmath > 3.0.0",
        "[ANALYZE] complex_module",
        "[DEPENDENCY] libnet != 1.3.0",
        "[DEPENDENCY] libmath <= 3.1.4",
        "[END BUILD]"
    ]
    for log in logs:
        await websocket.send(log)
        await asyncio.sleep(0.05)

start_server = websockets.serve(stream_logs, "localhost", 8080)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
