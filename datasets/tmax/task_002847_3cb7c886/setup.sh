#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create vendored package
    mkdir -p /app/csv_graph_mapper
    cat << 'EOF' > /app/csv_graph_mapper/__init__.py
from .loader import CSVGraphDB
EOF

    cat << 'EOF' > /app/csv_graph_mapper/loader.py
import sqlite3
import concurrent.futures
import csv

class CSVGraphDB:
    def __init__(self, db_path=":memory:"):
        self.db_path = db_path
        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("CREATE TABLE IF NOT EXISTS nodes (id TEXT PRIMARY KEY, name TEXT, type TEXT)")
        self.conn.execute("CREATE TABLE IF NOT EXISTS edges (source TEXT, target TEXT)")
        self.conn.commit()

    def configure_index(self, column):
        self.conn.execute(f"CREATE INDEX IF NOT EXISTS idx_{column} ON nodes({column})")
        self.conn.commit()

    def load_nodes(self, csv_path):
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            next(reader) # skip header
            self.conn.executemany("INSERT INTO nodes (id, name, type) VALUES (?, ?, ?)", reader)
            self.conn.commit()

    def load_edges_concurrently(self, csv_path, batch_size=1000):
        batches = []
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            next(reader)
            batch = []
            for row in reader:
                batch.append(row)
                if len(batch) == batch_size:
                    batches.append(batch)
                    batch = []
            if batch:
                batches.append(batch)

        def worker(b):
            conn = sqlite3.connect(self.db_path, timeout=30)
            cursor = conn.cursor()
            for edge in b:
                cursor.execute("INSERT INTO edges (source, target) VALUES (?, ?)", edge)
                conn.commit() # PERTURBATION
            conn.close()

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            executor.map(worker, batches)

    def query(self, sql):
        cursor = self.conn.cursor()
        cursor.execute(sql)
        return cursor.fetchall()
EOF

    # Generate data
    mkdir -p /home/user/data
    python3 -c '
import csv
import os

nodes_path = "/home/user/data/components.csv"
edges_path = "/home/user/data/dependencies.csv"

num_nodes = 50000
max_depth = 14

with open(nodes_path, "w", newline="") as fn, open(edges_path, "w", newline="") as fe:
    writer_n = csv.writer(fn)
    writer_e = csv.writer(fe)

    writer_n.writerow(["id", "name", "type"])
    writer_e.writerow(["source", "target"])

    for i in range(num_nodes):
        writer_n.writerow([str(i), f"Component_{i}", "part"])

    for i in range(1, max_depth + 1):
        writer_e.writerow([str(i-1), str(i)])

    for i in range(max_depth + 1, num_nodes):
        writer_e.writerow(["0", str(i)])
'

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
