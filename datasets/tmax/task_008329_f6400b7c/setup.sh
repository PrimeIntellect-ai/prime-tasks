#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import sqlite3
import os

conn = sqlite3.connect('/home/user/backups.db')
cursor = conn.cursor()

cursor.execute('''CREATE TABLE jobs (id TEXT PRIMARY KEY, duration INTEGER)''')
cursor.execute('''CREATE TABLE dependencies (job_id TEXT, depends_on_id TEXT)''')

jobs_data = [
    ('J1', 10),
    ('J2', 15),
    ('J3', 20),
    ('J4', 5),
    ('J5', 12),
    ('J6', 8),
    ('J7', 30),
    ('J8', 10)
]

deps_data = [
    ('J2', 'J1'),
    ('J3', 'J2'),
    ('J3', 'J1'),
    ('J4', 'J5'),
    ('J5', 'J6'),
    ('J6', 'J4'),
    ('J7', 'J6'),
    ('J8', 'J3')
]

cursor.executemany('INSERT INTO jobs VALUES (?, ?)', jobs_data)
cursor.executemany('INSERT INTO dependencies VALUES (?, ?)', deps_data)

conn.commit()
conn.close()
"

    chmod -R 777 /home/user
