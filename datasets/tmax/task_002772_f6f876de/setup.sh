#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/research_data.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
cursor.execute("CREATE TABLE tbl_nodes (node_id INTEGER PRIMARY KEY, p_title TEXT, p_year INTEGER)")
cursor.execute("CREATE TABLE tbl_edges (from_node INTEGER, to_node INTEGER)")
cursor.execute("CREATE TABLE tbl_creators (node_id INTEGER, creator_name TEXT)")

# Insert papers
papers = [
    (1, "Quantum Origins", 1998),
    (2, "Entanglement Dynamics", 2005),
    (3, "Subatomic Forces", 2001),
    (4, "Decoherence Models", 2010),
    (5, "Macroscopic Superposition", 2015),
    (6, "Deadlock avoidance in distributed databases", 1995)
]
cursor.executemany("INSERT INTO tbl_nodes VALUES (?, ?, ?)", papers)

# Insert authors
authors = [
    (1, "Alice Smith"), (1, "Bob Jones"),
    (2, "Charlie Brown"),
    (3, "Alice Smith"), (3, "David White"),
    (4, "Eve Davis"),
    (5, "Frank Miller"), (5, "Grace Hopper"), (5, "Alice Smith"),
    (6, "Dr. Deadlock")
]
cursor.executemany("INSERT INTO tbl_creators VALUES (?, ?)", authors)

# Insert edges
new_edges = [
    (1, 3), 
    (3, 4), 
    (4, 5), 
    (1, 2), 
    (2, 6), 
    (6, 2)  
]
cursor.executemany("INSERT INTO tbl_edges VALUES (?, ?)", new_edges)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
