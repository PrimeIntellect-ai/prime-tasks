#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest websockets

    mkdir -p /home/user/workspace/src
    cd /home/user/workspace

    cat << 'EOF' > src/modA.c
int getA() {
    return 10;
}
EOF

    cat << 'EOF' > src/modB.c
extern int getA();
int getB() {
    return getA() + 20;
}
EOF

    cat << 'EOF' > src/modC.c
extern int getA();
int getC() {
    return getA() + 30;
}
EOF

    cat << 'EOF' > src/modD.c
extern int getB();
extern int getC();
int getD() {
    return getB() + getC();
}
EOF

    cat << 'EOF' > ws_server.py
import asyncio
import websockets
import json

async def handler(websocket, path):
    graph = {
        "modA": [],
        "modB": ["modA"],
        "modC": ["modA"],
        "modD": ["modB", "modC"]
    }
    await websocket.send(json.dumps(graph))
    await asyncio.Future()  # run forever

start_server = websockets.serve(handler, "localhost", 8765)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
