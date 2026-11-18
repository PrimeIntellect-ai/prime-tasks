#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('backups.db')
c = conn.cursor()

# Create tables
c.execute('CREATE TABLE jobs (job_name TEXT PRIMARY KEY, duration INTEGER)')
c.execute('CREATE TABLE job_deps (parent_job TEXT, child_job TEXT)')

# Insert jobs
jobs = [
    ('ROOT', 0),
    ('A', 10),
    ('B', 10),
    ('C', 5),
    ('D', 20),
    ('LEAF', 15),
    ('E', 50)
]
c.executemany('INSERT INTO jobs VALUES (?, ?)', jobs)

# Insert dependencies (Graph)
deps = [
    ('ROOT', 'A'),
    ('ROOT', 'C'),
    ('A', 'B'),
    ('B', 'LEAF'),
    ('C', 'D'),
    ('D', 'LEAF'),
    ('ROOT', 'E'),
    ('E', 'LEAF')
]
c.executemany('INSERT INTO job_deps VALUES (?, ?)', deps)

# Create "corrupted" index (agent will drop or ignore it)
c.execute('CREATE INDEX idx_dep_parent ON job_deps(parent_job)')

conn.commit()
conn.close()
EOF

python3 setup_db.py
rm setup_db.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
