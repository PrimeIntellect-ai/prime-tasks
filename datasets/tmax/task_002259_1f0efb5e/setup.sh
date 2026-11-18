#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/backup_metadata.db')
cursor = conn.cursor()

# Create tables
cursor.execute('''CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, type TEXT)''')
cursor.execute('''CREATE TABLE edges (source_id INTEGER, target_id INTEGER)''')
cursor.execute('''CREATE TABLE backup_runs (id INTEGER PRIMARY KEY, node_id INTEGER, run_time DATETIME, status TEXT)''')

# Insert nodes
nodes = [
    (1, 'db_sales', 'database'),
    (2, 'table_orders', 'table'),
    (3, 'table_customers', 'table'),
    (4, 'view_daily_sales', 'view'),
    (5, 'export_job_s3', 'job'),
    (6, 'db_marketing', 'database'),
    (7, 'table_campaigns', 'table')
]
cursor.executemany('INSERT INTO nodes VALUES (?,?,?)', nodes)

# Insert edges (target depends on source)
# 1 -> 2
# 1 -> 3
# 2 -> 4
# 3 -> 4
# 4 -> 5
# 6 -> 7
edges = [
    (1, 2),
    (1, 3),
    (2, 4),
    (3, 4),
    (4, 5),
    (6, 7)
]
cursor.executemany('INSERT INTO edges VALUES (?,?)', edges)

# Insert backup runs
# db_sales failed
# table_orders failed
# table_customers succeeded
# view_daily_sales failed
# export_job_s3 failed
# db_marketing succeeded
# table_campaigns succeeded
runs = [
    # Historical runs
    (1, 1, '2023-10-01 10:00:00', 'SUCCESS'),
    (2, 2, '2023-10-01 10:05:00', 'SUCCESS'),
    (3, 4, '2023-10-01 10:10:00', 'SUCCESS'),

    # Latest runs
    (4, 1, '2023-10-02 10:00:00', 'FAILED'),
    (5, 2, '2023-10-02 10:05:00', 'FAILED'),
    (6, 3, '2023-10-02 10:05:00', 'SUCCESS'),
    (7, 4, '2023-10-02 10:10:00', 'FAILED'),
    (8, 5, '2023-10-02 10:15:00', 'FAILED'),
    (9, 6, '2023-10-02 10:00:00', 'SUCCESS'),
    (10, 7, '2023-10-02 10:05:00', 'SUCCESS'),
]
cursor.executemany('INSERT INTO backup_runs VALUES (?,?,?,?)', runs)

conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
