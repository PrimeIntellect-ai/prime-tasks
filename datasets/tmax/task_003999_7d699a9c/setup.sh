#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import json
import os

db_path = '/home/user/audit.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE system_graph (source TEXT, target TEXT, relation TEXT)''')
c.execute('''CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, user_id TEXT, resource TEXT, timestamp INTEGER, details_json TEXT)''')

# Graph Data
graph_data = [
    ('Alice', 'ServiceA', 'uses'),
    ('ServiceA', 'Customer_Data', 'reads'),
    ('Bob', 'Customer_Data', 'reads'),
    ('Charlie', 'ServiceB', 'uses'),
    ('ServiceB', 'ServiceC', 'calls'),
    ('ServiceC', 'Customer_Data', 'reads'),
    ('Dave', 'ServiceD', 'uses'),
    ('ServiceD', 'Customer_Data', 'reads'),
    ('Eve', 'ServiceA', 'uses')
]
c.executemany("INSERT INTO system_graph VALUES (?, ?, ?)", graph_data)

# Log Data
success = json.dumps({"status": "SUCCESS"})
denied = json.dumps({"status": "DENIED"})

logs = [
    (1, 'Alice', 'Customer_Data', 1000, success),
    (2, 'Alice', 'Customer_Data', 2000, success),
    (3, 'Alice', 'Customer_Data', 3000, success),
    (4, 'Alice', 'Customer_Data', 4000, success),
    (5, 'Dave', 'Customer_Data', 1000, success),
    (6, 'Dave', 'Customer_Data', 5000, success),
    (7, 'Dave', 'Customer_Data', 9000, success),
    (8, 'Dave', 'Customer_Data', 13000, success),
    (9, 'Eve', 'Customer_Data', 100, success),
    (10, 'Eve', 'Customer_Data', 200, success),
    (11, 'Eve', 'Customer_Data', 300, denied),
    (12, 'Eve', 'Customer_Data', 400, success),
    (13, 'Bob', 'Customer_Data', 100, success),
    (14, 'Bob', 'Customer_Data', 200, success),
    (15, 'Bob', 'Customer_Data', 300, success),
    (16, 'Bob', 'Customer_Data', 400, success),
]
c.executemany("INSERT INTO access_logs VALUES (?, ?, ?, ?, ?)", logs)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
