#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/backup.db')
c = conn.cursor()

c.execute('''CREATE TABLE fs_nodes (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    name TEXT,
    size INTEGER
)''')

nodes = [
    (1, None, 'root', 0),
    (2, 1, 'usr', 0),
    (3, 1, 'var', 0),
    (4, 2, 'bin', 0),
    (5, 4, 'bash', 1200),
    (6, 4, 'ls', 500),
    (7, 3, 'log', 0),
    (8, 7, 'syslog', 3000),
    (9, 7, 'auth.log', 800),
    (10, 1, 'etc', 0),
    (11, 10, 'passwd', 50),
    (12, 10, 'hosts', 20)
]

c.executemany('INSERT INTO fs_nodes VALUES (?,?,?,?)', nodes)

c.execute('CREATE INDEX idx_stale_size ON fs_nodes(size)')

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    chmod -R 777 /home/user
