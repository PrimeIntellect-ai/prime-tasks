#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/graph.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("CREATE TABLE Nodes (id INTEGER PRIMARY KEY, label TEXT, name TEXT)")
cursor.execute("CREATE TABLE Edges (src INTEGER, dst INTEGER, rel TEXT)")

nodes = [
    (1, 'User', 'Alice'),
    (2, 'User', 'Bob'),
    (3, 'User', 'Charlie'),
    (4, 'Service', 'WebApp'),
    (5, 'Service', 'AuthAPI'),
    (6, 'Service', 'PaymentGW'),
    (7, 'Database', 'UsersDB'),
    (8, 'Database', 'LogsDB'),
    (9, 'Database', 'TxDB')
]

edges = [
    (1, 4, 'MANAGES'),
    (2, 5, 'MANAGES'),
    (3, 6, 'MANAGES'),
    (1, 5, 'MANAGES'),
    (4, 7, 'DEPENDS_ON'),
    (4, 8, 'DEPENDS_ON'),
    (5, 7, 'DEPENDS_ON'),
    (6, 9, 'DEPENDS_ON'),
    (2, 6, 'IGNORES')
]

cursor.executemany("INSERT INTO Nodes VALUES (?, ?, ?)", nodes)
cursor.executemany("INSERT INTO Edges VALUES (?, ?, ?)", edges)

conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py
rm /tmp/setup_db.py

chmod -R 777 /home/user
