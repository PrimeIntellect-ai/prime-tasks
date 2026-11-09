#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nodejs npm nginx sqlite3
    pip3 install pytest websockets

    mkdir -p /home/user/telemetry_system

    sqlite3 /home/user/telemetry_system/db.sqlite3 "CREATE TABLE telemetry(id INTEGER PRIMARY KEY, data TEXT);"

    cat << 'EOF' > /home/user/telemetry_system/server.py
import asyncio
import websockets
import sqlite3

# Memory leak list
message_history = []

async def handle_connection(websocket, path):
    print "Client connected!" # Python 2 syntax error
    conn = sqlite3.connect('/home/user/telemetry_system/db.sqlite3')
    cursor = conn.cursor()
    try:
        async for message in websocket:
            print "Received: " + message
            message_history.append(message) # Leak
            cursor.execute("INSERT INTO device_telemetry (data) VALUES (?)", (message,))
            conn.commit()
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        conn.close()

start_server = websockets.serve(handle_connection, "127.0.0.1", 8080)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
