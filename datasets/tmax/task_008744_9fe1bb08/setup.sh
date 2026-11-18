#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pydantic jsonschema

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/transactions.db')
cursor = conn.cursor()
cursor.execute('''
    CREATE TABLE transactions (
        id INTEGER PRIMARY KEY,
        user_id TEXT,
        timestamp INTEGER,
        amount REAL
    )
''')

# Insert data
data = [
    # User A - Normal then anomaly
    (1, 'U_A', 1600000001, 10.0),
    (2, 'U_A', 1600000002, 12.0),
    (3, 'U_A', 1600000003, 11.0),
    (4, 'U_A', 1600000004, 9.0),
    (5, 'U_A', 1600000005, 10.0),
    (6, 'U_A', 1600000006, 25.0),
    (7, 'U_A', 1600000007, 40.0),
    (8, 'U_A', 1600000008, 15.0),

    # User B - Consistent
    (9, 'U_B', 1600000001, 100.0),
    (10, 'U_B', 1600000002, 100.0),
    (11, 'U_B', 1600000003, 100.0),
    (12, 'U_B', 1600000004, 100.0),
    (13, 'U_B', 1600000005, 100.0),
    (14, 'U_B', 1600000006, 100.0),

    # User C - Anomaly at exactly the 5th transaction
    (15, 'U_C', 1600000010, 5.0),
    (16, 'U_C', 1600000011, 5.0),
    (17, 'U_C', 1600000012, 5.0),
    (18, 'U_C', 1600000013, 5.0),
    (19, 'U_C', 1600000014, 25.0),
]

cursor.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?)', data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
