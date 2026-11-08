#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/access_graph.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("CREATE TABLE nodes (id TEXT PRIMARY KEY, label TEXT)")
c.execute("CREATE TABLE edges (source TEXT, target TEXT, relation TEXT)")

nodes = [
    ("U_Alice", "User"),
    ("U_Bob", "User"),
    ("U_Charlie", "User"),
    ("U_Dave", "User"),
    ("R_Admin", "Role"),
    ("R_Dev", "Role"),
    ("R_Guest", "Role"),
    ("S_Entry1", "Server"),
    ("S_Entry2", "Server"),
    ("S_Mid1", "Server"),
    ("S_Mid2", "Server"),
    ("S_Mid3", "Server"),
    ("DB_Main", "SecureDatabase"),
    ("DB_Backup", "SecureDatabase")
]

edges = [
    ("U_Alice", "R_Admin", "HAS_ROLE"),
    ("R_Admin", "S_Entry1", "CAN_ACCESS"),
    ("S_Entry1", "S_Mid1", "CONNECTS_TO"),
    ("S_Entry1", "S_Mid2", "CONNECTS_TO"),
    ("S_Mid1", "DB_Main", "CONNECTS_TO"),
    ("S_Mid2", "DB_Main", "CONNECTS_TO"),
    ("U_Bob", "R_Dev", "HAS_ROLE"),
    ("R_Dev", "S_Entry2", "CAN_ACCESS"),
    ("S_Entry2", "DB_Backup", "CONNECTS_TO"),
    ("S_Entry2", "S_Mid3", "CONNECTS_TO"),
    ("S_Mid3", "DB_Main", "CONNECTS_TO"),
    ("U_Charlie", "S_Entry1", "CONNECTS_TO"), 
    ("U_Charlie", "R_Guest", "HAS_ROLE"),
    ("R_Guest", "S_Entry1", "CAN_ACCESS"),
    ("U_Dave", "R_Dev", "HAS_ROLE"),
    ("U_Dave", "S_Entry1", "CONNECTS_TO")
]

c.executemany("INSERT INTO nodes VALUES (?, ?)", nodes)
c.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py

    chmod -R 777 /home/user
