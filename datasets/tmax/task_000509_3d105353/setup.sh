#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

mkdir -p /app/hyperquery
touch /app/hyperquery/__init__.py

cat << 'EOF' > /app/hyperquery/engine.py
import os
import sqlite3

def execute_query(query, params=None):
    if params is None:
        params = []
    db_path = os.environ.get("HYPER_DB_PATHH", ":memory:")
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute(query, params)
    results = cursor.fetchall()
    conn.commit()
    conn.close()
    return results
EOF

useradd -m -s /bin/bash user || true

sqlite3 /home/user/graph_data.db "CREATE TABLE nodes (id TEXT PRIMARY KEY, labels TEXT, properties JSON);"
sqlite3 /home/user/graph_data.db "CREATE TABLE edges (source TEXT, target TEXT, rel_type TEXT, properties JSON);"
sqlite3 /home/user/graph_data.db "INSERT INTO nodes VALUES ('n1', 'Item', '{\"category\": \"electronics\", \"price\": 100}');"
sqlite3 /home/user/graph_data.db "INSERT INTO nodes VALUES ('n2', 'User', '{\"category\": \"person\"}');"
sqlite3 /home/user/graph_data.db "INSERT INTO edges VALUES ('n2', 'n1', 'PURCHASED', '{\"date\": \"2023-01-01\"}');"

chmod -R 777 /app
chmod -R 777 /home/user
