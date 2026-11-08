#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server sqlite3
    pip3 install pytest websockets

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/ws_server.py
import asyncio
import websockets
import json

async def handler(websocket, path):
    if path != '/stream':
        return
    messages = [
        {"type": "schema", "table": "users", "columns": {"id": "int", "name": "string"}},
        {"type": "base_data", "table": "users", "data": {"id": 1, "name": "Alice"}},
        {"type": "patch", "table": "users", "id": 1, "patch": [{"op": "replace", "path": "/name", "value": "Alice Smith"}]},
        {"type": "schema_migration", "table": "users", "changes": [{"op": "add_column", "name": "email", "datatype": "string"}]},
        {"type": "patch", "table": "users", "id": 1, "patch": [{"op": "add", "path": "/email", "value": "alice@example.com"}]},
        {"type": "base_data", "table": "users", "data": {"id": 2, "name": "Bob"}},
        {"type": "patch", "table": "users", "id": 2, "patch": [{"op": "add", "path": "/email", "value": "bob@example.com"}]},
        {"type": "done"}
    ]
    for msg in messages:
        await websocket.send(json.dumps(msg))
        await asyncio.sleep(0.05)

start_server = websockets.serve(handler, "127.0.0.1", 8081)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    cat << 'EOF' >> /home/user/.bashrc
redis-server --daemonize yes --port 6379
nohup python3 /home/user/ws_server.py >/dev/null 2>&1 &
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
