#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import csv
import os

db_path = '/home/user/graph.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department TEXT)''')
c.execute('''CREATE TABLE connections (u1 INTEGER, u2 INTEGER, weight INTEGER)''')

# Insert users
users = []
for i in range(1, 101):
    dept = 'Engineering' if i <= 50 else 'HR'
    users.append((i, f"User_{i}", dept))
c.executemany('INSERT INTO users VALUES (?, ?, ?)', users)

# Insert connections
connections = []
# Triangle 1 (weight 30)
connections.append((1, 2, 10))
connections.append((2, 3, 10))
connections.append((1, 3, 10))

# Triangle 2 (weight 45)
connections.append((4, 5, 15))
connections.append((5, 6, 15))
connections.append((4, 6, 15))

# Triangle 3 (weight 60)
connections.append((10, 11, 20))
connections.append((11, 12, 20))
connections.append((10, 12, 20))

# Triangle 4 (weight 25)
connections.append((20, 21, 5))
connections.append((21, 22, 10))
connections.append((20, 22, 10))

# Triangle 5 (weight 50)
connections.append((30, 31, 20))
connections.append((31, 32, 15))
connections.append((30, 32, 15))

# Triangle 6 (weight 10 - should be excluded from top 5)
connections.append((40, 41, 2))
connections.append((41, 42, 4))
connections.append((40, 42, 4))

# HR triangle (should be excluded)
connections.append((60, 61, 100))
connections.append((61, 62, 100))
connections.append((60, 62, 100))

c.executemany('INSERT INTO connections VALUES (?, ?, ?)', connections)
conn.commit()
conn.close()

# Write bad query
bad_query = """SELECT u1.id as u1_id, u2.id as u2_id, u3.id as u3_id, (c1.weight + c2.weight + c3.weight) as total_weight
FROM users u1, users u2, users u3, connections c1, connections c2, connections c3
WHERE u1.department = 'Engineering' AND u2.department = 'Engineering' AND u3.department = 'Engineering'
  AND c1.u1 = u1.id AND c1.u2 = u2.id
  AND c2.u1 = u2.id AND c2.u2 = u3.id
  AND c3.weight > 0
  AND u1.id < u2.id AND u2.id < u3.id
ORDER BY total_weight DESC
LIMIT 5;
"""
with open('/home/user/bad_query.sql', 'w') as f:
    f.write(bad_query)
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
