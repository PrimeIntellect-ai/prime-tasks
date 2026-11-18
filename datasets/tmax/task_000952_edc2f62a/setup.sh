#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import sqlite3
import json

db_path = '/home/user/legacy_backup.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
shards = ['sales_na', 'sales_eu', 'sales_apac']
for shard in shards:
    cursor.execute(f'''
        CREATE TABLE {shard} (
            id INTEGER PRIMARY KEY,
            user_id INTEGER,
            amount REAL,
            status TEXT
        )
    ''')
    # Create an index that the prompt claims is corrupted
    cursor.execute(f'CREATE INDEX idx_status_{shard} ON {shard}(status)')

# Insert data
data = [
    ('sales_na', 101, 50.0, 'COMPLETED'),
    ('sales_na', 101, 100.5, 'COMPLETED'),
    ('sales_na', 102, 20.0, 'FAILED'),
    ('sales_na', 204, 30.0, 'COMPLETED'),

    ('sales_eu', 101, 200.0, 'COMPLETED'),
    ('sales_eu', 105, 10.0, 'COMPLETED'),
    ('sales_eu', 204, 40.0, 'PENDING'),

    ('sales_apac', 105, 500.0, 'COMPLETED'),
    ('sales_apac', 101, 10.0, 'FAILED'),
    ('sales_apac', 999, 99.9, 'COMPLETED')
]

for shard, user_id, amount, status in data:
    cursor.execute(f'INSERT INTO {shard} (user_id, amount, status) VALUES (?, ?, ?)', (user_id, amount, status))

# Create a non-sales table to test filtering
cursor.execute('''
    CREATE TABLE system_logs (
        id INTEGER PRIMARY KEY,
        message TEXT
    )
''')

conn.commit()
conn.close()

# Create target users JSON
target_users = [101, 105, 204, 300]
with open('/home/user/target_users.json', 'w') as f:
    json.dump(target_users, f)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
