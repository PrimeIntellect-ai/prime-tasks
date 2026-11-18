#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/setup.py
import sqlite3
import random

random.seed(42)

conn = sqlite3.connect('/home/user/data/architecture.db')
cursor = conn.cursor()

cursor.execute("CREATE TABLE nodes (id TEXT PRIMARY KEY, type TEXT)")
cursor.execute("CREATE TABLE edges (source TEXT, target TEXT, relation TEXT)")

# Create bad index
cursor.execute("CREATE INDEX idx_bad_edges ON edges(source) WHERE relation='depends_on'")

# Generate Nodes
nodes = []
for i in range(50):
    nodes.append((f"gw_{i}", "Gateway"))
for i in range(500):
    nodes.append((f"svc_{i}", "Service"))
for i in range(100):
    nodes.append((f"db_{i}", "Database"))

cursor.executemany("INSERT INTO nodes VALUES (?, ?)", nodes)

# Generate Edges
edges = []
# Gateway -> Service (Layer 1)
for i in range(50):
    for _ in range(random.randint(1, 5)):
        edges.append((f"gw_{i}", f"svc_{random.randint(0, 199)}", "calls"))

# Service -> Service (Layer 2)
for i in range(200):
    for _ in range(random.randint(0, 4)):
        edges.append((f"svc_{i}", f"svc_{random.randint(200, 499)}", "calls"))

# Service -> Database (Layer 3)
for i in range(200, 500):
    for _ in range(random.randint(0, 2)):
        edges.append((f"svc_{i}", f"db_{random.randint(0, 99)}", "calls"))

# Noise edges
for i in range(1000):
    edges.append((f"svc_{random.randint(0,499)}", f"svc_{random.randint(0,499)}", "depends_on"))

cursor.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)
conn.commit()
conn.close()
EOF

    python3 /home/user/data/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
