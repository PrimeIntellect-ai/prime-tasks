#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('sys_audit.db')
c = conn.cursor()

c.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT, name TEXT)")
c.execute("CREATE TABLE edges (source INTEGER, target INTEGER, relation TEXT)")
c.execute("CREATE INDEX idx_edges_source ON edges(source)")
c.execute("CREATE INDEX idx_edges_target ON edges(target)")

nodes = [
    (1, 'User', 'Alice'),
    (2, 'User', 'Bob'),
    (3, 'User', 'Eve'),
    (4, 'Department', 'Finance'),
    (5, 'Department', 'IT'),
    (6, 'Resource', 'Ledger'),
    (7, 'Resource', 'Server_Root')
]

edges = [
    (1, 4, 'MEMBER_OF'),
    (2, 5, 'MEMBER_OF'),
    (3, 5, 'MEMBER_OF'),
    (6, 4, 'BELONGS_TO'),
    (7, 5, 'BELONGS_TO'),
    (1, 6, 'ACCESSED'),
    (2, 7, 'ACCESSED'),
    (2, 6, 'ACCESSED'),
    (3, 6, 'ACCESSED')
]

c.executemany("INSERT INTO nodes VALUES (?, ?, ?)", nodes)
c.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)

conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
