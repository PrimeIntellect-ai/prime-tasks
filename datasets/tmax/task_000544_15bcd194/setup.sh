#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas duckdb

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import random

db_path = "/home/user/ecommerce.db"
jsonl_path = "/home/user/activity.jsonl"

# Deterministic seed for reproducible ground truth
random.seed(42)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE friendships (user_id1 INTEGER, user_id2 INTEGER)")
c.execute("CREATE TABLE purchases (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL)")

# Insert users
users = {i: f"User_{i}" for i in range(1, 26)}
for uid, name in users.items():
    c.execute("INSERT INTO users (id, name) VALUES (?, ?)", (uid, name))

# Create graph: Shortest path between 1 and 20 will be 1 -> 7 -> 14 -> 20
edges = [
    (1, 2), (2, 3), (3, 4), (1, 7), (7, 14), (14, 20),
    (1, 5), (5, 6), (14, 15), (20, 21), (7, 8)
]
for u, v in edges:
    c.execute("INSERT INTO friendships (user_id1, user_id2) VALUES (?, ?)", (u, v))
    c.execute("INSERT INTO friendships (user_id1, user_id2) VALUES (?, ?)", (v, u))

# Insert purchases
purchases = [
    (1, 1, 100.0), (2, 1, 50.0),
    (3, 7, 200.0), (4, 7, 10.0),
    (5, 14, 500.0),
    (6, 20, 150.0), (7, 20, 150.0),
    # Random other purchases
    (8, 2, 99.9)
]
for pid, uid, amt in purchases:
    c.execute("INSERT INTO purchases (id, user_id, amount) VALUES (?, ?, ?)", (pid, uid, amt))

conn.commit()
conn.close()

# Create JSONL
events = ["click", "scroll", "view"]
with open(jsonl_path, "w") as f:
    # Path users: 1, 7, 14, 20
    # User 1
    f.write(json.dumps({"user_id": 1, "event": "click", "duration_ms": 100}) + "\n")
    f.write(json.dumps({"user_id": 1, "event": "click", "duration_ms": 200}) + "\n")
    f.write(json.dumps({"user_id": 1, "event": "scroll", "duration_ms": 500}) + "\n")

    # User 7
    f.write(json.dumps({"user_id": 7, "event": "view", "duration_ms": 1000}) + "\n")

    # User 14
    f.write(json.dumps({"user_id": 14, "event": "click", "duration_ms": 50}) + "\n")
    f.write(json.dumps({"user_id": 14, "event": "scroll", "duration_ms": 300}) + "\n")
    f.write(json.dumps({"user_id": 14, "event": "scroll", "duration_ms": 400}) + "\n")

    # User 20
    f.write(json.dumps({"user_id": 20, "event": "view", "duration_ms": 800}) + "\n")
    f.write(json.dumps({"user_id": 20, "event": "view", "duration_ms": 900}) + "\n")

    # Other user
    f.write(json.dumps({"user_id": 2, "event": "click", "duration_ms": 100}) + "\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
