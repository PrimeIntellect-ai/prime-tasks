#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/backup_metadata.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
cursor.execute('''
CREATE TABLE services (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
)
''')

cursor.execute('''
CREATE TABLE dependencies (
    service_id INTEGER,
    depends_on_id INTEGER,
    FOREIGN KEY(service_id) REFERENCES services(id),
    FOREIGN KEY(depends_on_id) REFERENCES services(id)
)
''')

cursor.execute('''
CREATE TABLE backup_logs (
    job_id INTEGER PRIMARY KEY,
    service_id INTEGER,
    s3_uri TEXT,
    status TEXT,
    completion_time DATETIME,
    FOREIGN KEY(service_id) REFERENCES services(id)
)
''')

# Insert services
services = [
    (1, 'PaymentGateway'),
    (2, 'UserAuth'),
    (3, 'TransactionDB'),
    (4, 'RedisCache'),
    (5, 'NotificationService') # Unrelated
]
cursor.executemany('INSERT INTO services VALUES (?,?)', services)

# Insert dependencies: 
# PaymentGateway depends on UserAuth and TransactionDB
# UserAuth depends on RedisCache
dependencies = [
    (1, 2),
    (1, 3),
    (2, 4)
]
cursor.executemany('INSERT INTO dependencies VALUES (?,?)', dependencies)

# Insert backups
backups = [
    (101, 4, 's3://backups/redis/old.tar.gz', 'SUCCESS', '2023-10-01 10:00:00'),
    (102, 4, 's3://backups/redis/new.tar.gz', 'SUCCESS', '2023-10-02 10:00:00'),
    (103, 4, 's3://backups/redis/fail.tar.gz', 'FAILED', '2023-10-03 10:00:00'),

    (201, 2, 's3://backups/auth/v1.tar.gz', 'SUCCESS', '2023-10-01 11:00:00'),
    (202, 2, 's3://backups/auth/v2.tar.gz', 'FAILED', '2023-10-02 11:00:00'),

    (301, 3, 's3://backups/txdb/v1.tar.gz', 'SUCCESS', '2023-10-01 12:00:00'),
    (302, 3, 's3://backups/txdb/v2.tar.gz', 'SUCCESS', '2023-10-02 12:00:00'),

    (401, 1, 's3://backups/gateway/v1.tar.gz', 'SUCCESS', '2023-10-02 13:00:00')
]
cursor.executemany('INSERT INTO backup_logs VALUES (?,?,?,?,?)', backups)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
