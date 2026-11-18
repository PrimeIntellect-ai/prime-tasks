#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit

    python3 -c '
import sqlite3
import json

db_path = "/home/user/audit/active.sqlite"
json_path = "/home/user/audit/archived.json"

# Create SQLite data
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("CREATE TABLE transfers (tx_id TEXT, src_account TEXT, dst_account TEXT, amount REAL)")

sqlite_data = [
    ("TX01", "C-837", "C-500", 1000.0),
    ("TX02", "C-777", "C-500", 500.0),
    ("TX03", "C-901", "C-600", 200.0),
    ("TX04", "C-902", "C-600", 250.0),
    ("TX05", "C-903", "C-600", 300.0),
    ("TX06", "C-999", "C-837", 10000.0)
]

cur.executemany("INSERT INTO transfers VALUES (?, ?, ?, ?)", sqlite_data)
conn.commit()
conn.close()

# Create JSON data
json_data = [
    {"transaction_id": "TX07", "from_account": "C-500", "to_account": "C-600", "transfer_value": 1500.0},
    {"transaction_id": "TX08", "from_account": "C-600", "to_account": "C-102", "transfer_value": 1400.0},
    {"transaction_id": "TX09", "from_account": "C-904", "to_account": "C-600", "transfer_value": 100.0},
    {"transaction_id": "TX10", "from_account": "C-111", "to_account": "C-222", "transfer_value": 50.0}
]

with open(json_path, "w") as f:
    json.dump(json_data, f)
'

    chmod -R 777 /home/user
