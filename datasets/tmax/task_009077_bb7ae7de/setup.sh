#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    useradd -m -s /bin/bash user || true

    # Create the database setup script
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/supply_chain.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Create tables
c.execute('''CREATE TABLE facilities (id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE connections (source_id INTEGER, dest_id INTEGER, transit_time INTEGER, cost INTEGER)''')
c.execute('''CREATE TABLE disruptions (connection_id INTEGER, status TEXT)''')
c.execute('''CREATE TABLE cached_shortest_paths (source TEXT, dest TEXT, path TEXT, total_time INTEGER)''')

# Insert facilities
facilities = [
    (1, 'Origin-Alpha'),
    (2, 'Hub-X'),
    (3, 'Hub-Y'),
    (4, 'Dest-Omega'),
    (5, 'Trap-Hub')
]
c.executemany('INSERT INTO facilities VALUES (?, ?)', facilities)

# Insert connections
connections = [
    (1, 2, 10, 5),
    (2, 4, 10, 5),
    (1, 3, 15, 2),
    (3, 4, 15, 2),
    (1, 5, 5, 1),
    (5, 4, 5, 1),
    (1, 4, 50, 1)
]
c.executemany('INSERT INTO connections (source_id, dest_id, transit_time, cost) VALUES (?, ?, ?, ?)', connections)

# Insert disruptions
disruptions = [
    (2, 'active'),
    (6, 'active'),
    (4, 'resolved')
]
c.executemany('INSERT INTO disruptions VALUES (?, ?)', disruptions)

# Insert stale cached path (what the agent should NOT use)
c.execute("INSERT INTO cached_shortest_paths VALUES ('Origin-Alpha', 'Dest-Omega', 'Origin-Alpha,Trap-Hub,Dest-Omega', 10)")

conn.commit()
conn.close()
EOF

    # Run the setup script to create the DB
    python3 /tmp/setup_db.py

    # Ensure correct permissions
    chmod -R 777 /home/user
