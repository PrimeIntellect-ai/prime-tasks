#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import sqlite3
import os

db_path = '/home/user/backups.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.executescript('''
CREATE TABLE nodes (node_id TEXT PRIMARY KEY, region TEXT);
CREATE TABLE backups (backup_id TEXT PRIMARY KEY, node_id TEXT, size_gb INTEGER);
CREATE TABLE network_links (source TEXT, target TEXT, latency_ms INTEGER);

INSERT INTO nodes VALUES ('A', 'US-East'), ('B', 'US-East'), ('C', 'EU-West'), ('D', 'EU-West'), ('E', 'US-West'), ('F', 'US-West');

INSERT INTO backups VALUES ('b1', 'A', 100), ('b2', 'A', 150), ('b3', 'B', 50), ('b4', 'C', 200), ('b5', 'D', 300), ('b6', 'D', 50);

INSERT INTO network_links VALUES 
('A', 'B', 10), 
('B', 'C', 50), 
('A', 'C', 70), 
('C', 'F', 20), 
('B', 'F', 80), 
('A', 'E', 100), 
('E', 'F', 10);
''')
conn.commit()
conn.close()

broken_script = """import sqlite3

def generate_report():
    conn = sqlite3.connect('/home/user/backups.db')
    cur = conn.cursor()

    # Broken cross join query
    cur.execute("SELECT region, SUM(size_gb) FROM nodes, backups GROUP BY region ORDER BY region")
    totals = cur.fetchall()

    with open('/home/user/report_output.txt', 'w') as f:
        f.write("--- Total Size Per Region ---\\n")
        for row in totals:
            f.write(f"{row[0]}: {row[1]} GB\\n")

    conn.close()

if __name__ == '__main__':
    generate_report()
"""
with open('/home/user/report.py', 'w') as f:
    f.write(broken_script)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
