#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import sqlite3

conn = sqlite3.connect('/home/user/services.db')
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE services (
    id INTEGER PRIMARY KEY,
    service_name TEXT NOT NULL
)
''')

cursor.execute('''
CREATE TABLE dependencies (
    caller_id INTEGER,
    callee_id INTEGER,
    FOREIGN KEY(caller_id) REFERENCES services(id),
    FOREIGN KEY(callee_id) REFERENCES services(id)
)
''')

services = [
    (1, 'frontend'),
    (2, 'api_gateway'),
    (3, 'auth_service'),
    (4, 'user_db'),
    (5, 'payment_service'),
    (6, 'checkout_ui'),
    (7, 'inventory_service'),
    (8, 'product_db'),
    (9, 'recommendation_engine'),
    (10, 'analytics_service')
]

cursor.executemany('INSERT INTO services VALUES (?, ?)', services)

edges = [
    (1, 2),
    (2, 3),
    (3, 4),
    (5, 3),
    (6, 5),
    (7, 8),
    (2, 7),
    (9, 8),
    (10, 4)
]

cursor.executemany('INSERT INTO dependencies VALUES (?, ?)', edges)
conn.commit()
conn.close()
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
