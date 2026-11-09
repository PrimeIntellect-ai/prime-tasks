#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)
db_path = '/home/user/backup_meta.db'

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('''
CREATE TABLE clusters (
    id INTEGER PRIMARY KEY,
    name TEXT
)
''')

cur.execute('''
CREATE TABLE storage_nodes (
    id INTEGER PRIMARY KEY,
    cluster_id INTEGER,
    node_name TEXT,
    FOREIGN KEY(cluster_id) REFERENCES clusters(id)
)
''')

cur.execute('''
CREATE TABLE backups (
    id INTEGER PRIMARY KEY,
    storage_node_id INTEGER,
    backup_type TEXT,
    parent_backup_id INTEGER,
    size_bytes INTEGER,
    status TEXT,
    timestamp DATETIME,
    FOREIGN KEY(storage_node_id) REFERENCES storage_nodes(id)
)
''')

# Insert data
cur.execute("INSERT INTO clusters (id, name) VALUES (1, 'us-east-cluster'), (2, 'eu-west-cluster')")
cur.execute("INSERT INTO storage_nodes (id, cluster_id, node_name) VALUES (10, 1, 'node-e1'), (20, 2, 'node-w1')")

# Chain 1 for us-east (length 3)
cur.execute("INSERT INTO backups VALUES (100, 10, 'FULL', NULL, 5000, 'SUCCESS', '2023-10-01 10:00:00')")
cur.execute("INSERT INTO backups VALUES (101, 10, 'INC', 100, 500, 'SUCCESS', '2023-10-02 10:00:00')")
cur.execute("INSERT INTO backups VALUES (102, 10, 'INC', 101, 200, 'SUCCESS', '2023-10-03 10:00:00')")
cur.execute("INSERT INTO backups VALUES (103, 10, 'INC', 102, 100, 'FAILED', '2023-10-04 10:00:00')") # Failed, ignored in window

# Chain 2 for eu-west (length 5)
cur.execute("INSERT INTO backups VALUES (200, 20, 'FULL', NULL, 8000, 'SUCCESS', '2023-10-01 11:00:00')")
cur.execute("INSERT INTO backups VALUES (201, 20, 'INC', 200, 1000, 'SUCCESS', '2023-10-02 11:00:00')")
cur.execute("INSERT INTO backups VALUES (202, 20, 'INC', 201, 800, 'SUCCESS', '2023-10-03 11:00:00')")
cur.execute("INSERT INTO backups VALUES (203, 20, 'INC', 202, 600, 'SUCCESS', '2023-10-04 11:00:00')")
cur.execute("INSERT INTO backups VALUES (204, 20, 'INC', 203, 300, 'SUCCESS', '2023-10-05 11:00:00')")

conn.commit()
conn.close()

# Create flawed script
script_content = """import sqlite3
import csv
import sys

def generate_report():
    conn = sqlite3.connect('/home/user/backup_meta.db')
    cur = conn.cursor()

    # FLAWED QUERY WITH IMPLICIT CROSS JOIN
    query = '''
        SELECT c.name, SUM(b.size_bytes)
        FROM clusters c, storage_nodes s, backups b
        WHERE c.id = s.cluster_id
          AND b.status = 'SUCCESS'
        GROUP BY c.name
    '''

    cur.execute(query)
    rows = cur.fetchall()

    writer = csv.writer(sys.stdout)
    writer.writerow(['cluster_name', 'total_size'])
    for row in rows:
        writer.writerow(row)

if __name__ == "__main__":
    generate_report()
"""

with open('/home/user/report.py', 'w') as f:
    f.write(script_content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
