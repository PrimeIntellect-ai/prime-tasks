#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc binutils
    pip3 install pytest

    mkdir -p /home/user/legacy
    cd /home/user

    # Create SQLite database
    sqlite3 /home/user/legacy/db.sqlite "CREATE TABLE metrics (id INTEGER PRIMARY KEY, raw_val INTEGER);"
    sqlite3 /home/user/legacy/db.sqlite "INSERT INTO metrics (id, raw_val) VALUES (1, 100);"
    sqlite3 /home/user/legacy/db.sqlite "INSERT INTO metrics (id, raw_val) VALUES (2, 255);"
    sqlite3 /home/user/legacy/db.sqlite "INSERT INTO metrics (id, raw_val) VALUES (3, 0);"

    # Create Python script
    cat << 'EOF' > /home/user/legacy/processor.py
import sqlite3
import ctypes
import os

lib_path = os.path.join(os.path.dirname(__file__), 'libcustom.so')
lib = ctypes.CDLL(lib_path)

lib.compute_hash.argtypes = [ctypes.c_int]
lib.compute_hash.restype = ctypes.c_int

conn = sqlite3.connect(os.path.join(os.path.dirname(__file__), 'db.sqlite'))
cursor = conn.cursor()

cursor.execute("SELECT id, raw_val FROM metrics")
rows = cursor.fetchall()

for row in rows:
    row_id, raw_val = row
    computed = lib.compute_hash(raw_val)
    cursor.execute("UPDATE metrics SET hash_val = ? WHERE id = ?", (computed, row_id))

conn.commit()
conn.close()
EOF
    chmod +x /home/user/legacy/processor.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
