#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    # Create setup script for DB
    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/backup_metadata.db')
cursor = conn.cursor()

cursor.executescript('''
CREATE TABLE databases (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE storage_nodes (id TEXT PRIMARY KEY, name TEXT, region TEXT);
CREATE TABLE backup_jobs (id INTEGER PRIMARY KEY, db_id INTEGER, storage_id TEXT, size_bytes INTEGER, timestamp DATETIME);
CREATE TABLE replication_links (source_id TEXT, target_id TEXT);

INSERT INTO databases (id, name) VALUES (1, 'prod-db-1'), (2, 'billing-db');

INSERT INTO storage_nodes (id, name, region) VALUES 
('s1', 'node_A', 'us-east'),
('s2', 'node_B', 'us-west'),
('s3', 'node_C', 'eu-central'),
('s4', 'node_Z', 'archive'),
('s5', 'node_X', 'us-east'),
('s6', 'node_Y', 'archive');

-- billing-db has 3 backups
INSERT INTO backup_jobs (id, db_id, storage_id, size_bytes, timestamp) VALUES 
(1, 2, 's1', 5000, '2023-10-01 10:00:00'),
(2, 2, 's1', 5200, '2023-10-02 10:00:00'),
(3, 2, 's1', 5300, '2023-10-03 10:00:00'); -- Latest backup for billing-db is on s1

-- prod-db-1 backups
INSERT INTO backup_jobs (id, db_id, storage_id, size_bytes, timestamp) VALUES 
(4, 1, 's2', 10000, '2023-10-03 10:00:00');

-- Replication Graph (s1 -> s3 -> s4(archive))  (s1 -> s5 -> s2 -> s6(archive))
INSERT INTO replication_links (source_id, target_id) VALUES 
('s1', 's3'),
('s3', 's4'),
('s1', 's5'),
('s5', 's2'),
('s2', 's6'),
('s2', 's4');
''')
conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py

    # Create the buggy script
    cat << 'EOF' > /home/user/generate_report.py
import sqlite3
import sys
import json

def generate_report(db_name):
    conn = sqlite3.connect('/home/user/backup_metadata.db')
    cursor = conn.cursor()

    # Buggy query with implicit cross join
    query = f"""
    SELECT d.name, SUM(b.size_bytes) OVER (PARTITION BY d.id) as total_size
    FROM databases d, backup_jobs b, storage_nodes s
    WHERE d.name = '{db_name}'
    LIMIT 1;
    """

    cursor.execute(query)
    res = cursor.fetchone()
    total_size = res[1] if res else 0

    # TODO: Implement shortest path graph traversal to archive
    shortest_path = []

    output = {
        "database_name": db_name,
        "correct_total_backup_size": total_size,
        "shortest_archive_path": shortest_path
    }

    with open('/home/user/report.json', 'w') as f:
        json.dump(output, f, indent=2)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        generate_report(sys.argv[1])
    else:
        print("Provide db name")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
