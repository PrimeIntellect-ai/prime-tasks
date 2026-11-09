#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/metrics_service

cat << 'EOF' > /tmp/setup.py
import os
import sqlite3
import py_compile

db_path = '/home/user/metrics_service/data.db'
conn = sqlite3.connect(db_path, isolation_level=None)
conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('CREATE TABLE measurements (id INTEGER PRIMARY KEY, value REAL);')
conn.execute('INSERT INTO measurements (value) VALUES (15.5);')
conn.execute('INSERT INTO measurements (value) VALUES (24.2);')
conn.execute('INSERT INTO measurements (value) VALUES (10.3);')

dump_path = '/home/user/metrics_service/memory.dump'
with open(dump_path, 'wb') as f:
    f.write(os.urandom(1024))
    f.write(b'\x00\x00SECRET_MULTIPLIER=459\x00\x00')
    f.write(os.urandom(1024))

calc_code = """
import sqlite3

def calculate_metric(db_path, multiplier):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT value FROM measurements")
    rows = cursor.fetchall()

    total = sum(row[0] for row in rows)
    # BROKEN FORMULA:
    result = total + multiplier
    return result
"""
calc_path = '/home/user/metrics_service/calculator.py'
with open(calc_path, 'w') as f:
    f.write(calc_code)

py_compile.compile(calc_path, cfile='/home/user/metrics_service/calculator.pyc')
os.remove(calc_path)

# Exit hard to prevent SQLite from cleaning up the WAL file
os._exit(0)
EOF

python3 /tmp/setup.py

chmod -R 777 /home/user
