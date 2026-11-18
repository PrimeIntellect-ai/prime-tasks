#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

mkdir -p /home/user
cd /home/user

# Create database and tables
sqlite3 backup.db "CREATE TABLE directories(id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT);"
sqlite3 backup.db "CREATE TABLE files(id INTEGER PRIMARY KEY, dir_id INTEGER, name TEXT, size INTEGER);"

# Insert directories
sqlite3 backup.db "INSERT INTO directories VALUES(1, NULL, 'root');"
sqlite3 backup.db "INSERT INTO directories VALUES(2, 1, 'target_dir');"
sqlite3 backup.db "INSERT INTO directories VALUES(3, 2, 'sub1');"
sqlite3 backup.db "INSERT INTO directories VALUES(4, 3, 'sub2');"
sqlite3 backup.db "INSERT INTO directories VALUES(5, 1, 'other_dir');"
sqlite3 backup.db "INSERT INTO directories VALUES(6, 5, 'sub3');"

# Insert files
sqlite3 backup.db "INSERT INTO files VALUES(1, 2, 'f1', 100);"
sqlite3 backup.db "INSERT INTO files VALUES(2, 3, 'f2', 200);"
sqlite3 backup.db "INSERT INTO files VALUES(3, 4, 'f3', 300);"
sqlite3 backup.db "INSERT INTO files VALUES(4, 6, 'f4', 400);"

# Create index
sqlite3 backup.db "CREATE INDEX idx_parent ON directories(parent_id);"

# Simulate index corruption
sqlite3 backup.db "PRAGMA writable_schema = ON; UPDATE sqlite_master SET sql = 'CREATE INDEX idx_parent ON directories(parent_id)' WHERE name = 'idx_parent'; PRAGMA writable_schema = OFF;"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
