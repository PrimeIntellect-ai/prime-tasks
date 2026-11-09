#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

db_path = '/home/user/network.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create schema
cursor.execute('''CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT)''')
cursor.execute('''CREATE TABLE connections (source_id INTEGER, target_id INTEGER, FOREIGN KEY(source_id) REFERENCES servers(id), FOREIGN KEY(target_id) REFERENCES servers(id))''')
cursor.execute('''CREATE TABLE traffic_logs (conn_source INTEGER, conn_target INTEGER, bytes_transferred INTEGER, timestamp TEXT)''')

# Insert servers
servers = [
    (1, 'Gateway-01'),
    (2, 'Node-2'),
    (3, 'Node-3'),
    (4, 'Node-4'),
    (5, 'Node-5'),
    (6, 'Node-6'),
    (7, 'Node-7'),
    (8, 'Node-8'),
    (9, 'Node-9'),
    (10, 'Database-Cluster')
]
cursor.executemany('INSERT INTO servers VALUES (?, ?)', servers)

# Insert connections
connections = [
    (1, 2), (2, 3), (3, 10),
    (1, 4), (4, 5), (5, 6), (6, 10),
    (1, 7), (7, 10),
    (1, 8), (8, 9), (9, 10),
    (7, 2), (4, 8)
]
cursor.executemany('INSERT INTO connections VALUES (?, ?)', connections)

# Insert traffic logs
traffic = [
    (1, 2, 100, '2023-01-01'), (2, 3, 200, '2023-01-01'), (3, 10, 300, '2023-01-01'),
    (1, 4, 150, '2023-01-01'), (4, 5, 250, '2023-01-01'), (5, 6, 350, '2023-01-01'), (6, 10, 450, '2023-01-01'),
    (1, 7, 500, '2023-01-01'), (7, 10, 1500, '2023-01-01'),
    (1, 8, 50, '2023-01-01'), (8, 9, 50, '2023-01-01'), (9, 10, 50, '2023-01-01'),
    (7, 2, 999, '2023-01-01'), (4, 8, 888, '2023-01-01')
]
cursor.executemany('INSERT INTO traffic_logs VALUES (?, ?, ?, ?)', traffic)

conn.commit()
conn.close()

# Create bad_report.py
with open('/home/user/bad_report.py', 'w') as f:
    f.write("""import sqlite3

conn = sqlite3.connect('/home/user/network.db')
cursor = conn.cursor()

# HORRIBLE IMPLICIT CROSS JOIN
cursor.execute('SELECT SUM(t.bytes_transferred) FROM servers s1, servers s2, traffic_logs t')
result = cursor.fetchone()[0]
print(f"Total Traffic Calculated: {result}")
conn.close()
""")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
