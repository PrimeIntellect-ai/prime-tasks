#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Vendor peewee
    mkdir -p /app/peewee
    pip3 install peewee==3.16.3 --target /app/peewee
    # Mutate peewee
    sed -i "s/INNER = 'INNER'/INNER = 'INNNER'/g" /app/peewee/peewee.py

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/get_metrics_oracle.py
import sys
import sqlite3

def run(dc, min_size):
    conn = sqlite3.connect('/home/user/backup_metrics.db')
    cursor = conn.cursor()

    query = """
    WITH 
    ValidServers AS (
        SELECT DISTINCT s.id, s.hostname 
        FROM servers s
        JOIN backups b ON s.id = b.server_id
        WHERE s.datacenter = ? AND b.size_bytes > ?
    ),
    LatestBackup AS (
        SELECT server_id, status 
        FROM (
            SELECT server_id, status, ROW_NUMBER() OVER(PARTITION BY server_id ORDER BY timestamp DESC) as rn
            FROM backups
        ) WHERE rn = 1
    ),
    TotalSize AS (
        SELECT server_id, SUM(size_bytes) as total_size
        FROM backups 
        WHERE status = 'SUCCESS'
        GROUP BY server_id
    ),
    RestoreStats AS (
        SELECT b.server_id, 
               COUNT(r.id) as total_restores,
               SUM(CASE WHEN r.is_successful = 1 THEN 1 ELSE 0 END) as successful_restores
        FROM backups b
        LEFT JOIN restores r ON b.id = r.backup_id
        GROUP BY b.server_id
    )
    SELECT vs.hostname, 
           lb.status, 
           COALESCE(ts.total_size, 0),
           rs.total_restores,
           rs.successful_restores
    FROM ValidServers vs
    LEFT JOIN LatestBackup lb ON vs.id = lb.server_id
    LEFT JOIN TotalSize ts ON vs.id = ts.server_id
    LEFT JOIN RestoreStats rs ON vs.id = rs.server_id
    ORDER BY vs.hostname ASC
    """

    cursor.execute(query, (dc, min_size))
    for row in cursor.fetchall():
        hostname = row[0]
        latest_status = row[1]
        total_size = row[2]
        total_restores = row[3]
        succ_restores = row[4]

        if total_restores is None or total_restores == 0:
            rate_str = "N/A"
        else:
            rate = (succ_restores / total_restores) * 100.0
            rate_str = f"{rate:.2f}"

        print(f"{hostname},{latest_status},{total_size},{rate_str}")

if __name__ == "__main__":
    run(sys.argv[1], int(sys.argv[2]))
EOF

    # Create user
    useradd -m -s /bin/bash user || true

    # Create and populate database
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/backup_metrics.db')
c = conn.cursor()

c.execute("CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT, datacenter TEXT);")
c.execute("CREATE TABLE backups (id INTEGER PRIMARY KEY, server_id INTEGER, timestamp INTEGER, size_bytes INTEGER, status TEXT, FOREIGN KEY(server_id) REFERENCES servers(id));")
c.execute("CREATE TABLE restores (id INTEGER PRIMARY KEY, backup_id INTEGER, is_successful INTEGER, duration_sec INTEGER, FOREIGN KEY(backup_id) REFERENCES backups(id));")

datacenters = ['us-east-1', 'eu-west-1', 'ap-south-1', 'us-west-2']
statuses = ['SUCCESS', 'FAILED', 'PENDING']

for i in range(1, 51):
    c.execute("INSERT INTO servers (id, hostname, datacenter) VALUES (?, ?, ?)", 
              (i, f"server-{i:03d}.local", random.choice(datacenters)))

for i in range(1, 501):
    server_id = random.randint(1, 50)
    timestamp = 1600000000 + random.randint(0, 10000000)
    size_bytes = random.randint(10000, 10000000000)
    status = random.choice(statuses)
    c.execute("INSERT INTO backups (id, server_id, timestamp, size_bytes, status) VALUES (?, ?, ?, ?, ?)",
              (i, server_id, timestamp, size_bytes, status))

for i in range(1, 201):
    backup_id = random.randint(1, 500)
    is_successful = random.choice([0, 1])
    duration = random.randint(10, 3600)
    c.execute("INSERT INTO restores (id, backup_id, is_successful, duration_sec) VALUES (?, ?, ?, ?)",
              (i, backup_id, is_successful, duration))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    # Set permissions
    chmod -R 777 /home/user
