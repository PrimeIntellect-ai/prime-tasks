#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar sqlite3
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Download and vendor networkx 3.1
    mkdir -p /app
    cd /app
    wget https://pypi.python.org/packages/source/n/networkx/networkx-3.1.tar.gz
    tar -xzf networkx-3.1.tar.gz
    mv networkx-3.1 networkx-source
    rm networkx-3.1.tar.gz

    # Apply deliberate bug
    python3 -c '
import os
unweighted_path = "/app/networkx-source/networkx/algorithms/shortest_paths/unweighted.py"
with open(unweighted_path, "r") as f:
    content = f.read()

content = content.replace(
    "def single_source_shortest_path_length(G, source, cutoff=None):\n",
    "def single_source_shortest_path_length(G, source, cutoff=None):\n    if cutoff is not None: cutoff -= 1\n"
)
content = content.replace(
    "def single_target_shortest_path_length(G, target, cutoff=None):\n",
    "def single_target_shortest_path_length(G, target, cutoff=None):\n    if cutoff is not None: cutoff -= 1\n"
)

with open(unweighted_path, "w") as f:
    f.write(content)
'

    # Generate corpora
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/corpora/clean

    python3 -c '
import sqlite3
import os
from datetime import datetime, timedelta

def create_db(path, transactions):
    conn = sqlite3.connect(path)
    c = conn.cursor()
    c.execute("""CREATE TABLE transactions
                 (id INTEGER PRIMARY KEY, source_account TEXT, target_account TEXT, amount REAL, timestamp TEXT)""")
    c.executemany("INSERT INTO transactions (id, source_account, target_account, amount, timestamp) VALUES (?, ?, ?, ?, ?)", transactions)
    conn.commit()
    conn.close()

base_time = datetime(2023, 1, 1, 12, 0, 0)

# Generate Evil DBs (Condition A & B met)
for i in range(20):
    txs = []
    # Condition A: 4 transactions within 24h, sum > 50000
    for j in range(4):
        txs.append((j+1, "ACC_A", f"ACC_B{j}", 15000.0, (base_time + timedelta(hours=j)).isoformat()))
    # Condition B: SANCTIONED_1 -> N1 -> N2 -> CLEARED_1 (3 hops)
    txs.append((10, "SANCTIONED_1", "N1", 100.0, base_time.isoformat()))
    txs.append((11, "N1", "N2", 100.0, base_time.isoformat()))
    txs.append((12, "N2", "CLEARED_1", 100.0, base_time.isoformat()))
    create_db(f"/home/user/corpora/evil/evil_{i}.db", txs)

# Generate Clean DBs (Condition A not met OR Condition B not met)
for i in range(20):
    txs = []
    if i % 2 == 0:
        # Fails Condition A (sum < 50000) but meets B
        for j in range(4):
            txs.append((j+1, "ACC_A", f"ACC_B{j}", 1000.0, (base_time + timedelta(hours=j)).isoformat()))
        txs.append((10, "SANCTIONED_1", "N1", 100.0, base_time.isoformat()))
        txs.append((11, "N1", "N2", 100.0, base_time.isoformat()))
        txs.append((12, "N2", "CLEARED_1", 100.0, base_time.isoformat()))
    else:
        # Meets Condition A but fails B (4 hops)
        for j in range(4):
            txs.append((j+1, "ACC_A", f"ACC_B{j}", 15000.0, (base_time + timedelta(hours=j)).isoformat()))
        txs.append((10, "SANCTIONED_1", "N1", 100.0, base_time.isoformat()))
        txs.append((11, "N1", "N2", 100.0, base_time.isoformat()))
        txs.append((12, "N2", "N3", 100.0, base_time.isoformat()))
        txs.append((13, "N3", "CLEARED_1", 100.0, base_time.isoformat()))
    create_db(f"/home/user/corpora/clean/clean_{i}.db", txs)
'

    chmod -R 777 /home/user
    chmod -R 777 /app/networkx-source
