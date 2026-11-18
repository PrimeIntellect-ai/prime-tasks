#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/iam_graph.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT, name TEXT)''')
c.execute('''CREATE TABLE edges (source_id INTEGER, rel_type TEXT, target_id INTEGER)''')

nodes = [
    (1, 'USER', 'Alice'),
    (2, 'USER', 'Bob'),
    (3, 'USER', 'Charlie'),
    (4, 'USER', 'Dave'),
    (5, 'USER', 'Eve'),
    (6, 'USER', 'Frank'),
    (10, 'ROLE', 'Employee'),
    (11, 'ROLE', 'Accountant'),
    (12, 'ROLE', 'Senior_Accountant'),
    (13, 'ROLE', 'Finance_Director'),
    (14, 'ROLE', 'IT_Support'),
    (15, 'ROLE', 'SysAdmin'),
    (16, 'ROLE', 'External_Auditor'),
    (20, 'ASSET', 'FINANCIAL_LEDGER'),
    (21, 'ASSET', 'HR_RECORDS')
]

edges = [
    (13, 'INHERITS', 12),
    (12, 'INHERITS', 11),
    (11, 'INHERITS', 10),
    (15, 'INHERITS', 14),
    (10, 'CAN_READ', 20),
    (12, 'CAN_WRITE', 20),
    (15, 'CAN_WRITE', 20),
    (16, 'CAN_READ', 20),
    (13, 'CAN_WRITE', 21),
    (1, 'HAS_ROLE', 10),
    (2, 'HAS_ROLE', 11),
    (3, 'HAS_ROLE', 12),
    (4, 'HAS_ROLE', 13),
    (5, 'HAS_ROLE', 14),
    (6, 'HAS_ROLE', 15),
]

c.executemany('INSERT INTO nodes VALUES (?, ?, ?)', nodes)
c.executemany('INSERT INTO edges VALUES (?, ?, ?)', edges)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
