#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl espeak-ng sqlite3 cargo rustc ffmpeg
    pip3 install pytest

    mkdir -p /app /backups

    # Generate handover.wav
    espeak-ng -w /app/handover.wav "Hey, it's Alex. The storage array corrupted around epoch 1684321000. We lost the 'orders' database completely. Please generate the restore plan for the orders database up to that timestamp."

    # Generate catalog.db
    cat << 'EOF' > /app/init_db.py
import sqlite3

conn = sqlite3.connect('/app/catalog.db')
cursor = conn.cursor()

cursor.execute("CREATE TABLE databases (name VARCHAR PRIMARY KEY)")
cursor.execute("CREATE TABLE dependencies (db_name VARCHAR, depends_on VARCHAR)")
cursor.execute("CREATE TABLE backups (id INTEGER PRIMARY KEY, db_name VARCHAR, type VARCHAR, timestamp INTEGER, filepath VARCHAR)")

dbs = ['users', 'inventory', 'billing', 'orders', 'notifications']
for db in dbs:
    cursor.execute("INSERT INTO databases VALUES (?)", (db,))

deps = [
    ('orders', 'users'),
    ('orders', 'inventory'),
    ('inventory', 'users'),
    ('billing', 'users'),
    ('notifications', 'users')
]
for db, dep in deps:
    cursor.execute("INSERT INTO dependencies VALUES (?, ?)", (db, dep))

ts_start = 1600000000
backup_id = 1
for db in dbs:
    for i in range(10):
        ts = ts_start + i * 10000000
        cursor.execute("INSERT INTO backups VALUES (?, ?, 'F', ?, ?)", (backup_id, db, ts, f"/backups/{db}_full_{ts}.bak"))
        backup_id += 1
        for j in range(1, 6):
            inc_ts = ts + j * 1000000
            cursor.execute("INSERT INTO backups VALUES (?, ?, 'I', ?, ?)", (backup_id, db, inc_ts, f"/backups/{db}_inc_{inc_ts}.bak"))
            backup_id += 1

conn.commit()
conn.close()
EOF
    python3 /app/init_db.py
    rm /app/init_db.py

    # Create oracle_planner
    cat << 'EOF' > /app/oracle_planner
#!/usr/bin/env python3
import sys
import sqlite3
from collections import defaultdict

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    target_db = sys.argv[1]
    target_ts = int(sys.argv[2])

    conn = sqlite3.connect('/app/catalog.db')
    cursor = conn.cursor()

    required_dbs = set([target_db])
    queue = [target_db]

    cursor.execute("SELECT db_name, depends_on FROM dependencies")
    deps = cursor.fetchall()

    depends_on_map = defaultdict(list)
    for db, dep in deps:
        depends_on_map[db].append(dep)

    while queue:
        curr = queue.pop(0)
        for dep in depends_on_map[curr]:
            if dep not in required_dbs:
                required_dbs.add(dep)
                queue.append(dep)

    in_degree = {db: 0 for db in required_dbs}
    graph = defaultdict(list)

    for db in required_dbs:
        for dep in depends_on_map[db]:
            if dep in required_dbs:
                graph[dep].append(db)
                in_degree[db] += 1

    sorted_dbs = []
    zero_in_degree = [db for db in required_dbs if in_degree[db] == 0]

    while zero_in_degree:
        zero_in_degree.sort()
        curr = zero_in_degree.pop(0)
        sorted_dbs.append(curr)
        for neighbor in graph[curr]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                zero_in_degree.append(neighbor)

    for db in sorted_dbs:
        cursor.execute('''
            SELECT id, timestamp, filepath FROM backups
            WHERE db_name = ? AND type = 'F' AND timestamp <= ?
            ORDER BY timestamp DESC LIMIT 1
        ''', (db, target_ts))
        full_backup = cursor.fetchone()

        if not full_backup:
            continue

        full_id, full_ts, full_filepath = full_backup
        print(full_filepath)

        cursor.execute('''
            SELECT filepath FROM backups
            WHERE db_name = ? AND type = 'I' AND timestamp > ? AND timestamp <= ?
            ORDER BY timestamp ASC
        ''', (db, full_ts, target_ts))

        for (filepath,) in cursor.fetchall():
            print(filepath)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_planner

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
