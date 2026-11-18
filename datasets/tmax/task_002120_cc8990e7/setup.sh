#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

conn = sqlite3.connect('/home/user/network.db')
cursor = conn.cursor()

cursor.execute('''
    CREATE TABLE users (
        user_id INTEGER PRIMARY KEY,
        username TEXT UNIQUE NOT NULL
    )
''')

cursor.execute('''
    CREATE TABLE follows (
        follower_id INTEGER NOT NULL,
        followee_id INTEGER NOT NULL,
        PRIMARY KEY (follower_id, followee_id)
    )
''')

users = [
    (1, 'omega_node'),
    (2, 'user_A'),
    (3, 'user_B'),
    (4, 'user_C'),
    (5, 'user_D'),
    (6, 'user_E'),
    (7, 'user_F'),
    (8, 'noise_1'),
    (9, 'noise_2')
]
cursor.executemany("INSERT INTO users VALUES (?, ?)", users)

follows = [
    (2, 1),
    (3, 1),
    (4, 1),
    (5, 2),
    (6, 2),
    (6, 3),
    (7, 3),
    (1, 3),
    (4, 3),
    (8, 9),
    (9, 8)
]
cursor.executemany("INSERT INTO follows VALUES (?, ?)", follows)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py

    chmod -R 777 /home/user
