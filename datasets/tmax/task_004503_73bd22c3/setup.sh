#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user
cd /home/user

python3 -c "
import sqlite3
conn = sqlite3.connect('backups.db')
c = conn.cursor()
c.execute('CREATE TABLE backups (id INTEGER PRIMARY KEY, type TEXT, status TEXT, size INTEGER, timestamp INTEGER)')
c.execute('CREATE TABLE dependencies (parent_id INTEGER, child_id INTEGER)')

backups = [
    (1, 'FULL', 'SUCCESS', 1000, 100),
    (2, 'INCR', 'SUCCESS', 150, 200),
    (3, 'INCR', 'FAILED', 50, 300),
    (4, 'DIFF', 'SUCCESS', 400, 400),
    (5, 'INCR', 'SUCCESS', 100, 500),
    (6, 'INCR', 'SUCCESS', 120, 600),
    (7, 'FULL', 'SUCCESS', 1200, 700),
    (8, 'DIFF', 'SUCCESS', 200, 800),
    (99, 'INCR', 'SUCCESS', 50, 900)
]
c.executemany('INSERT INTO backups VALUES (?, ?, ?, ?, ?)', backups)

deps = [
    (1, 2),
    (2, 3),
    (3, 5),
    (1, 4),
    (4, 5),
    (5, 6),
    (6, 99),
    (7, 8),
    (8, 99)
]
c.executemany('INSERT INTO dependencies VALUES (?, ?)', deps)
conn.commit()
conn.close()
"

chmod -R 777 /home/user
