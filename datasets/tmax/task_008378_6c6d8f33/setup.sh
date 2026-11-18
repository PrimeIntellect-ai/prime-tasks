#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/numsock_repo/numsock
    cd /home/user/numsock_repo

    cat << 'EOF' > pyproject.toml
[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project]
name = "numsock
version = "0.1.0"
dependencies = [
    # missing dependency here
]
EOF

    cat << 'EOF' > numsock/__init__.py
EOF

    cat << 'EOF' > numsock/db.py
import sqlite3

def init_db(db_path="data.db"):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS records (id INTEGER PRIMARY KEY, value FLOAT)''')
    conn.commit()
    return conn

def insert_record(conn, value, ema):
    c = conn.cursor()
    # BUG in previous version: only inserted value. Patch fixes this.
    c.execute("INSERT INTO records (value) VALUES (?)", (value,))
    conn.commit()
EOF

    cat << 'EOF' > pr_migration.patch
--- numsock/db.py
+++ numsock/db.py
@@ -4,7 +4,7 @@
 def init_db(db_path="data.db"):
     conn = sqlite3.connect(db_path)
     c = conn.cursor()
-    c.execute('''CREATE TABLE IF NOT EXISTS records (id INTEGER PRIMARY KEY, value FLOAT)''')
+    c.execute('''CREATE TABLE IF NOT EXISTS records (id INTEGER PRIMARY KEY, value FLOAT, ema FLOATX)''')
     conn.commit()
     return conn

-def insert_record(conn, value):
+def insert_record(conn, value, ema):
     c = conn.cursor()
-    c.execute("INSERT INTO records (value) VALUES (?)", (value,))
+    c.execute("INSERT INTO records (value, ema) VALUES (?, ?)", (value, ema))
     conn.commit()
EOF

    cat << 'EOF' > numsock/server.py
import asyncio
import json
import websockets
from numsock.db import init_db, insert_record

last_ema = None
conn = init_db("data.db")

async def handler(websocket):
    global last_ema
    async for message in websocket:
        # BUG: Doesn't parse JSON, doesn't calculate EMA correctly
        data = message
        val = float(data)

        ema = val # BROKEN EMA ALGORITHM

        insert_record(conn, val, ema)
        await websocket.send(str(ema))

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

    cat << 'EOF' > test_client.py
import asyncio
import websockets
import json

async def test():
    async with websockets.connect("ws://localhost:8765") as ws:
        for v in [10.0, 20.0, 15.0]:
            await ws.send(json.dumps({"value": v}))
            resp = await ws.recv()
            print(f"Sent {v}, got {resp}")

if __name__ == "__main__":
    asyncio.run(test())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
