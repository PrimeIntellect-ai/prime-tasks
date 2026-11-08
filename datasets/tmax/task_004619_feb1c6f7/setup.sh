#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/setup_db.py
import sqlite3
import os

db_path = '/home/user/graph.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE Nodes (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE Edges (source_id INTEGER, target_id INTEGER, relation_type TEXT)')

nodes = [
    (1, 'AuthService'),
    (2, 'UserService'),
    (3, 'EmailService'),
    (4, 'PaymentService'),
    (5, 'LedgerService'),
    (6, 'AuditService'),
    (7, 'NotificationService'),
    (8, 'ReportService'),
    (9, 'DataService')
]
c.executemany('INSERT INTO Nodes VALUES (?, ?)', nodes)

edges = [
    # Cycle 1: Auth (1) -> User (2) -> Email (3) -> Auth (1)
    (1, 2, 'DEPENDS_ON'),
    (2, 3, 'DEPENDS_ON'),
    (3, 1, 'DEPENDS_ON'),

    # Cycle 2: Payment (4) -> Ledger (5) -> Audit (6) -> Payment (4)
    (4, 5, 'DEPENDS_ON'),
    (5, 6, 'DEPENDS_ON'),
    (6, 4, 'DEPENDS_ON'),

    # Fake Cycle (Wrong relation type)
    (7, 8, 'REQUIRES'),
    (8, 9, 'REQUIRES'),
    (9, 7, 'REQUIRES'),

    # Incomplete cycle
    (1, 4, 'DEPENDS_ON'),
    (4, 7, 'DEPENDS_ON')
]
c.executemany('INSERT INTO Edges VALUES (?, ?, ?)', edges)

conn.commit()
conn.close()
EOF

python3 /home/user/setup_db.py
rm /home/user/setup_db.py

chmod -R 777 /home/user
