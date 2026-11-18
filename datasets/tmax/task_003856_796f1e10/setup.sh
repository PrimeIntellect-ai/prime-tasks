#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/build_workspace/data
    cd /home/user/build_workspace

    python3 -c '
import sqlite3

conn = sqlite3.connect("results.db")
conn.execute("PRAGMA journal_mode=WAL;")
conn.execute("CREATE TABLE records (id INTEGER PRIMARY KEY, value INTEGER);")

for i in range(1, 51):
    if i == 42: continue
    conn.execute("INSERT INTO records (id, value) VALUES (?, ?)", (i, i))

conn.commit()
'

    python3 -c '
import json
data = {"id": 42, "value": 42}
with open("/home/user/build_workspace/data/data_42.json", "w", encoding="utf-16le") as f:
    json.dump(data, f)
'

    chmod -R 777 /home/user
