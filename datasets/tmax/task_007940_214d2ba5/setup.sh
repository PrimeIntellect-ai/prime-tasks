#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/service_mesh.db')
c = conn.cursor()

c.execute('''CREATE TABLE services (id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE dependencies (source_id INTEGER, target_id INTEGER, version INTEGER, is_active INTEGER)''')

services = [
    (1, 'api-gateway'),
    (2, 'auth-service'),
    (3, 'user-db'),
    (4, 'cache-redis'),
    (5, 'payment-service'),
    (6, 'notification-service')
]
c.executemany("INSERT INTO services VALUES (?, ?)", services)

edges = [
    # api-gateway -> auth-service
    (1, 2, 1, 1),
    (1, 2, 2, 0),
    (1, 2, 3, 1), # active

    # api-gateway -> payment-service
    (1, 5, 1, 1), # active

    # payment-service -> user-db
    (5, 3, 1, 1),
    (5, 3, 2, 1), # active

    # auth-service -> user-db
    (2, 3, 1, 0),
    (2, 3, 2, 1), # active

    # api-gateway -> cache-redis
    (1, 4, 1, 1),
    (1, 4, 2, 0), # inactive in latest

    # auth-service -> cache-redis
    (2, 4, 1, 1), # active

    # notification-service -> user-db
    (6, 3, 1, 1), # active

    # payment-service -> notification-service
    (5, 6, 1, 1),
    (5, 6, 2, 0)  # inactive in latest
]
c.executemany("INSERT INTO dependencies VALUES (?, ?, ?, ?)", edges)

conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
