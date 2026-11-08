#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/etl_tasks.db')
c = conn.cursor()
c.execute('''CREATE TABLE tasks (id TEXT, parent_id TEXT, status TEXT, exec_time INTEGER)''')

data = [
    ('ROOT', None, 'SUCCESS', 10),
    ('A', 'ROOT', 'SUCCESS', 20),
    ('B', 'ROOT', 'SUCCESS', 15),
    ('C', 'A', 'SUCCESS', 30),
    ('D', 'A', 'FAILED', 10),
    ('D1', 'D', 'SUCCESS', 100),
    ('E', 'B', 'SUCCESS', 5),
    ('F', 'B', 'SUCCESS', 40),
    ('G', 'C', 'SUCCESS', 10),
    ('H', 'C', 'SUCCESS', 15),
    ('I', 'E', 'SUCCESS', 20),
    ('J', 'F', 'SUCCESS', 25),
    ('K', 'H', 'SUCCESS', 5),
    ('L', 'I', 'SUCCESS', 10),
    ('M', 'J', 'SUCCESS', 10),
    ('N', 'M', 'SUCCESS', 5)
]

c.executemany('INSERT INTO tasks VALUES (?,?,?,?)', data)
conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py

    chmod -R 777 /home/user
