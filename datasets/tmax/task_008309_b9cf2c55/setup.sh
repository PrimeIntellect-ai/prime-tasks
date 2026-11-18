#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3
import json

db_path = '/home/user/audit.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''CREATE TABLE logs (document TEXT)''')

events = [
    {"type": "login", "user": "Alice", "timestamp": "2023-10-01T10:00:00Z"},
    {"type": "approval", "details": {"requester": "Alice", "approver": "Bob"}, "resource": "DB_Prod"},
    {"type": "approval", "details": {"requester": "Bob", "approver": "Charlie"}, "resource": "Server_1"},
    {"type": "approval", "details": {"requester": "Charlie", "approver": "Alice"}, "resource": "Firewall"},
    {"type": "logout", "user": "Bob", "timestamp": "2023-10-01T12:00:00Z"},
    {"type": "approval", "details": {"requester": "David", "approver": "Eve"}, "resource": "DB_Test"},
    {"type": "approval", "details": {"requester": "Eve", "approver": "Frank"}, "resource": "Server_2"},
    {"type": "approval", "details": {"requester": "Grace", "approver": "Heidi"}, "resource": "VPN"},
    {"type": "approval", "details": {"requester": "Heidi", "approver": "Grace"}, "resource": "VPN"},
    {"type": "approval", "details": {"requester": "Ivan", "approver": "Judy"}, "resource": "Email"},
    {"type": "login", "user": "Zack", "timestamp": "2023-10-02T09:00:00Z"}
]

for event in events:
    cursor.execute("INSERT INTO logs (document) VALUES (?)", (json.dumps(event),))

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
