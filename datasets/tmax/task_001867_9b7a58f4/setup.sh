#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the database setup script
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

db_path = '/home/user/corporate_audit.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE ownership_graph (owner_id INTEGER, subsidiary_id INTEGER)')

# Insert noise
data = []
for i in range(2000, 10000):
    data.append((random.randint(2000, 9999), random.randint(2000, 9999)))

# Insert the specific cycle: 1001 -> 5555 -> 6666 -> 7777 -> 1001
cycle = [(1001, 5555), (5555, 6666), (6666, 7777), (7777, 1001)]
data.extend(cycle)

# Insert a dead end from 1001
data.extend([(1001, 8888), (8888, 9999)])

c.executemany('INSERT INTO ownership_graph VALUES (?, ?)', data)
conn.commit()
conn.close()
EOF

    # Run the setup script
    python3 /tmp/setup_db.py

    # Clean up
    rm /tmp/setup_db.py

    # Set permissions
    chmod -R 777 /home/user
