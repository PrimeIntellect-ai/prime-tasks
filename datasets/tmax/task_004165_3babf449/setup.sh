#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/network.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE users (user_id INTEGER PRIMARY KEY, name TEXT, region TEXT)''')
c.execute('''CREATE TABLE messages (msg_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER)''')
c.execute('''CREATE TABLE connections (user1_id INTEGER, user2_id INTEGER)''')

users = [
    (1, 'Alice', 'North'),
    (2, 'Bob', 'North'),
    (3, 'Charlie', 'South'),
    (4, 'Diana', 'South'),
    (5, 'Eve', 'East'),
    (6, 'Frank', 'West'),
    (7, 'Grace', 'North'),
    (8, 'Hank', 'South')
]
c.executemany('INSERT INTO users VALUES (?,?,?)', users)

messages = [
    (1, 1, 2), (2, 1, 3), (3, 1, 4), (4, 1, 5), (5, 1, 6),
    (6, 2, 1), (7, 2, 3),
    (8, 3, 1), (9, 3, 2), (10, 3, 4), (11, 3, 5),
    (12, 4, 1),
    (13, 7, 2)
]
c.executemany('INSERT INTO messages VALUES (?,?,?)', messages)

connections = [
    (1, 2), (1, 5),
    (2, 7),
    (5, 6),
    (6, 3),
    (3, 4),
    (4, 8)
]
c.executemany('INSERT INTO connections VALUES (?,?)', connections)
reverse_connections = [(v, u) for u, v in connections]
c.executemany('INSERT INTO connections VALUES (?,?)', reverse_connections)

conn.commit()
conn.close()

with open('/home/user/aggregate.sql', 'w') as f:
    f.write('''SELECT u.user_id, u.region, count(m.msg_id) as msg_count,
       DENSE_RANK() OVER(PARTITION BY u.region ORDER BY count(m.msg_id) DESC) as rank
FROM users u, messages m
GROUP BY u.user_id, u.region;
''')
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
