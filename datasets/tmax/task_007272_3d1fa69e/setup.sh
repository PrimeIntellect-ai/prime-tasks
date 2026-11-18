#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/infrastructure.db')
c = conn.cursor()

c.execute('''CREATE TABLE services (service_id INTEGER PRIMARY KEY, service_name TEXT, is_active INTEGER)''')
c.execute('''CREATE TABLE dependencies (dependency_id INTEGER PRIMARY KEY, provider_id INTEGER, consumer_id INTEGER)''')
c.execute('''CREATE TABLE backups (backup_id INTEGER PRIMARY KEY, service_id INTEGER, timestamp INTEGER, status TEXT)''')

services = [
    (1, 'db-auth', 1),
    (2, 'db-users', 1),
    (3, 'db-logs', 0), # inactive
    (4, 'api-gateway', 1),
    (5, 'payment-worker', 1),
    (6, 'cache-node', 1)
]
c.executemany("INSERT INTO services VALUES (?, ?, ?)", services)

dependencies = [
    (1, 1, 4), # api-gateway depends on db-auth
    (2, 2, 4), # api-gateway depends on db-users
    (3, 1, 5), # payment-worker depends on db-auth
    (4, 3, 5), # payment-worker depends on inactive db-logs
    (5, 6, 2)  # db-users depends on cache-node
]
c.executemany("INSERT INTO dependencies VALUES (?, ?, ?)", dependencies)

backups = [
    (1, 1, 1600000000, 'FAILED'),
    (2, 2, 1600000100, 'SUCCESS'),
    (3, 3, 1600000200, 'FAILED'),
    (4, 4, 1600000300, 'SUCCESS'),
    (5, 6, 1600000400, 'FAILED')
]
c.executemany("INSERT INTO backups VALUES (?, ?, ?, ?)", backups)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
