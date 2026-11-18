#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/architecture.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE services (
    id INTEGER PRIMARY KEY,
    service_name TEXT UNIQUE NOT NULL
)
''')

cursor.execute('''
CREATE TABLE dependencies (
    caller_id INTEGER,
    callee_id INTEGER,
    is_critical BOOLEAN,
    PRIMARY KEY (caller_id, callee_id),
    FOREIGN KEY (caller_id) REFERENCES services(id),
    FOREIGN KEY (callee_id) REFERENCES services(id)
)
''')

services = [
    (1, 'PaymentGateway'),
    (2, 'OrderService'),
    (3, 'CartService'),
    (4, 'NotificationService'),
    (5, 'UserDashboard'),
    (6, 'AnalyticsService')
]
cursor.executemany("INSERT INTO services VALUES (?, ?)", services)

dependencies = [
    (2, 1, 1),
    (3, 2, 1),
    (5, 3, 1),
    (4, 1, 0),
    (6, 2, 1),
    (1, 6, 1)
]
cursor.executemany("INSERT INTO dependencies VALUES (?, ?, ?)", dependencies)

conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py
rm /tmp/setup_db.py

chmod -R 777 /home/user
