#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app

    # Create the hidden logic for the legacy binary
    cat << 'EOF' > /app/.hidden_logic.py
import sys, sqlite3, json, time
if len(sys.argv) != 3: sys.exit(1)
conn = sqlite3.connect(sys.argv[1])
conn.row_factory = sqlite3.Row
c = conn.cursor()
nodes, edges = [], []

for row in c.execute("SELECT * FROM users"):
    nodes.append({"id": f"u_{row['id']}", "label": "User", "properties": {"username": row['username'], "joined": row['created_at']}})

for row in c.execute("SELECT * FROM devices"):
    nodes.append({"id": f"d_{row['id']}", "label": "Device", "properties": {"type": row['device_type'], "os": row['os_version']}})
    edges.append({"source": f"u_{row['user_id']}", "target": f"d_{row['id']}", "type": "OWNS"})

for row in c.execute("SELECT * FROM logins"):
    edges.append({"source": f"u_{row['user_id']}", "target": f"d_{row['device_id']}", "type": "LOGGED_IN", "properties": {"time": row['timestamp'], "ip": row['ip_address']}})

nodes.sort(key=lambda x: x['id'])
edges.sort(key=lambda x: (x['source'], x['target'], x.get('type', '')))

time.sleep(2) # Simulate slowness

with open(sys.argv[2], 'w') as f:
    json.dump({"nodes": nodes, "edges": edges}, f)
EOF

    # Create a C wrapper to act as the stripped binary
    cat << 'EOF' > /app/wrapper.c
#include <stdlib.h>
#include <stdio.h>
int main(int argc, char *argv[]) {
    if(argc != 3) {
        fprintf(stderr, "Usage: %s <input.sqlite> <output.json>\n", argv[0]);
        return 1;
    }
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "python3 /app/.hidden_logic.py %s %s", argv[1], argv[2]);
    return system(cmd);
}
EOF

    gcc -O2 /app/wrapper.c -o /app/legacy_graph_backup
    strip /app/legacy_graph_backup
    rm /app/wrapper.c

    useradd -m -s /bin/bash user || true

    # Create the sample database
    cat << 'EOF' > /tmp/make_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/prod_backup.sqlite')
c = conn.cursor()
c.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, created_at TEXT)")
c.execute("CREATE TABLE devices (id INTEGER PRIMARY KEY, user_id INTEGER, device_type TEXT, os_version TEXT)")
c.execute("CREATE TABLE logins (id INTEGER PRIMARY KEY, user_id INTEGER, device_id INTEGER, timestamp TEXT, ip_address TEXT)")

for i in range(1, 10001):
    c.execute("INSERT INTO users VALUES (?, ?, ?)", (i, f"user_{i}", "2023-01-01"))
    c.execute("INSERT INTO devices VALUES (?, ?, ?, ?)", (i, i, "phone", "v1"))
    c.execute("INSERT INTO logins VALUES (?, ?, ?, ?, ?)", (i, i, i, "2023-01-02", "127.0.0.1"))

conn.commit()
conn.close()
EOF

    python3 /tmp/make_db.py
    rm /tmp/make_db.py

    chmod -R 777 /app
    chmod -R 777 /home/user
