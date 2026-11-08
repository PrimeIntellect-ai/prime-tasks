#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/network.db')
c = conn.cursor()

c.execute('CREATE TABLE servers (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE links (source_id INTEGER, target_id INTEGER, bandwidth REAL)')

servers = [
    (1, 'Start'),
    (2, 'N1'),
    (3, 'N2'),
    (4, 'N3'),
    (5, 'End')
]
c.executemany('INSERT INTO servers VALUES (?, ?)', servers)

links = [
    (1, 2, 1000),
    (1, 3, 800),
    (1, 4, 500),
    (2, 5, 100),
    (3, 5, 200),
    (4, 5, 10000)
]
c.executemany('INSERT INTO links VALUES (?, ?, ?)', links)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    cat << 'EOF' > /home/user/buggy_query.sql
SELECT s1.name AS source, s2.name AS target, l.bandwidth
FROM servers s1, servers s2, links l;
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
