#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

db_path = '/home/user/graph.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE entity_links (src INT, dst INT, rel VARCHAR(50))')

edges = [
    (10, 20, 'friend'),
    (20, 30, 'friend'),
    (30, 10, 'friend'),
    (5, 15, 'friend'),
    (15, 25, 'friend'),
    (25, 5, 'friend'),
    (60, 50, 'friend'),
    (50, 40, 'friend'),
    (100, 200, 'follower'),
    (200, 300, 'follower'),
    (300, 100, 'follower'),
    (10, 5, 'friend')
]

c.executemany('INSERT INTO entity_links VALUES (?, ?, ?)', edges)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
