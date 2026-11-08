#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/components.db')
c = conn.cursor()
c.execute('CREATE TABLE nodes(id TEXT PRIMARY KEY, type TEXT, cost REAL)')
c.execute('CREATE TABLE edges(source TEXT, target TEXT)')

nodes = [
    ('ROOT_01', 'root', 0.0),
    ('LIB_A1', 'library', 15.5),
    ('LIB_A2', 'library', 10.0),
    ('SVC_B1', 'service', 50.0),
    ('SVC_B2', 'service', 25.0),
    ('SVC_B3', 'service', 30.0),
    ('ORPHAN', 'service', 999.0)
]
c.executemany('INSERT INTO nodes VALUES (?,?,?)', nodes)

edges = [
    ('ROOT_01', 'LIB_A1'),
    ('ROOT_01', 'SVC_B1'),
    ('LIB_A1', 'LIB_A2'),
    ('SVC_B1', 'SVC_B2'),
    ('SVC_B2', 'SVC_B3')
]
c.executemany('INSERT INTO edges VALUES (?,?)', edges)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
