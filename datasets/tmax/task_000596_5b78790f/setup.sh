#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev cargo rustc
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/etl

python3 << 'EOF'
import sqlite3
conn = sqlite3.connect('/home/user/data.db')
c = conn.cursor()
c.execute('CREATE TABLE users (user_id INTEGER PRIMARY KEY, username TEXT)')
c.execute('CREATE TABLE events (event_id INTEGER PRIMARY KEY, user_id INTEGER, event_date TEXT, score REAL, comment TEXT)')
c.executemany('INSERT INTO users VALUES (?, ?)', [(1, 'alice'), (2, 'bob')])
c.executemany('INSERT INTO events VALUES (?, ?, ?, ?, ?)', [
    (101, 1, '2023-01-01', 10.0, 'First event'),
    (102, 1, '2023-01-03', 20.0, 'Second event\nwith newline'),
    (103, 1, '2023-01-05', 30.0, 'Third event'),
    (104, 1, '2023-01-07', 40.0, 'Fourth event'),
    (201, 2, '2023-01-02', 15.0, 'Bob first'),
    (202, 2, '2023-01-04', 25.0, 'Bob second\nline2\nline3'),
    (203, 2, '2023-01-06', 5.0, 'Bob third')
])
conn.commit()
conn.close()
EOF

chmod -R 777 /home/user
