#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest websockets

    mkdir -p /home/user/qa_env

    # 1. Initial Database
    sqlite3 /home/user/qa_env/test_db.sqlite "CREATE TABLE state (id INTEGER PRIMARY KEY, status TEXT); INSERT INTO state (id, status) VALUES (1, 'init');"

    # 2. Migration File
    cat << 'EOF' > /home/user/qa_env/v2_migration.sql
ALTER TABLE state ADD COLUMN version INTEGER DEFAULT 1;
UPDATE state SET version = 2 WHERE id = 1;
EOF

    # 3. Mock Server
    cat << 'EOF' > /home/user/qa_env/mock_server.py
import asyncio
import websockets
import sqlite3
import json

async def handler(websocket, path):
    async for message in websocket:
        data = json.loads(message)
        if data.get("cmd") == "get_state":
            conn = sqlite3.connect('/home/user/qa_env/test_db.sqlite')
            conn.row_factory = sqlite3.Row
            cur = conn.cursor()
            cur.execute("SELECT * FROM state WHERE id = 1")
            row = cur.fetchone()
            conn.close()
            response = dict(row) if row else {}
            await websocket.send(json.dumps({"response": response}))

start_server = websockets.serve(handler, "127.0.0.1", 9999)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    # 4. WebSocket Client
    cat << 'EOF' > /home/user/qa_env/ws_client.py
import asyncio
import websockets
import sys

async def send_msg(payload):
    async with websockets.connect("ws://127.0.0.1:9999") as websocket:
        await websocket.send(payload)
        response = await websocket.recv()
        print(response, end="")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        asyncio.get_event_loop().run_until_complete(send_msg(sys.argv[1]))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
