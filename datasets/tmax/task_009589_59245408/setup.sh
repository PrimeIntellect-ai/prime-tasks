#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > create_db.py
import sqlite3

conn = sqlite3.connect('/home/user/raw_data.db')
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE sensor (
    timestamp TEXT,
    temperature TEXT,
    pressure TEXT
)
''')

data = [
    ('2023-01-01 00:10:00', '30.0C', '1002'),
    ('2023-01-01 00:00:00', '15.0C', '1000'),
    ('2023-01-01 00:20:00', '14.0', '1004'),
    ('2023-01-01 00:05:00', '59.0F', '1001'),
    ('2023-01-01 00:15:00', '25.0C', '1003')
]

cursor.executemany('INSERT INTO sensor VALUES (?, ?, ?)', data)
conn.commit()
conn.close()
EOF

    python3 create_db.py
    rm create_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
