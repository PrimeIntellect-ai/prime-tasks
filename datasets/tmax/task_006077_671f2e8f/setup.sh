#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

db_path = '/home/user/supply_chain.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE locations (
    loc_id INTEGER PRIMARY KEY,
    loc_name TEXT,
    loc_type TEXT
)
''')

cursor.execute('''
CREATE TABLE links (
    start_loc INTEGER,
    end_loc INTEGER,
    transit_time INTEGER,
    is_open INTEGER
)
''')

# Insert locations
locations = [
    (1, 'Factory_Alpha', 'Factory'),
    (2, 'Warehouse_A', 'Warehouse'),
    (3, 'Warehouse_B', 'Warehouse'),
    (4, 'Warehouse_C', 'Warehouse'),
    (5, 'Warehouse_D', 'Warehouse'),
    (6, 'Warehouse_E', 'Warehouse'),
    (7, 'Warehouse_F', 'Warehouse'),
    (8, 'Cross_Dock_1', 'CrossDock')
]
cursor.executemany("INSERT INTO locations VALUES (?, ?, ?)", locations)

# Insert links
links = [
    (1, 2, 10, 1), # F -> A: 10
    (1, 3, 15, 1), # F -> B: 15
    (1, 8, 5, 1),  # F -> CD: 5
    (8, 4, 12, 1), # CD -> C: 12 (Total F->C = 17)
    (2, 5, 5, 1),  # A -> D: 5 (Total F->D = 15)
    (3, 6, 2, 1),  # B -> E: 2 (Total F->E = 17)
    (1, 7, 30, 1), # F -> F: 30
    (1, 9, 1, 0),  # Inactive link
    (8, 5, 1, 0)   # Inactive link
]
cursor.executemany("INSERT INTO links VALUES (?, ?, ?, ?)", links)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
