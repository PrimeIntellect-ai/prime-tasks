#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/logistics.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
cursor.execute('''
CREATE TABLE locations (
    loc_id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT
)
''')

cursor.execute('''
CREATE TABLE routes (
    route_id INTEGER PRIMARY KEY,
    source_id INTEGER,
    dest_id INTEGER,
    distance REAL,
    FOREIGN KEY(source_id) REFERENCES locations(loc_id),
    FOREIGN KEY(dest_id) REFERENCES locations(loc_id)
)
''')

cursor.execute('''
CREATE TABLE shipments (
    shipment_id INTEGER PRIMARY KEY,
    route_id INTEGER,
    timestamp DATETIME,
    FOREIGN KEY(route_id) REFERENCES routes(route_id)
)
''')

# Insert locations
locations = [
    (1, 'Alpha_Station', 'Warehouse'),
    (2, 'Beta_Hub', 'Distribution'),
    (3, 'Gamma_Point', 'Warehouse'),
    (4, 'Delta_Depot', 'Distribution')
]
cursor.executemany('INSERT INTO locations VALUES (?, ?, ?)', locations)

# Insert routes
routes = [
    (101, 1, 2, 50.0), # Alpha to Beta
    (102, 1, 3, 30.0), # Alpha to Gamma
    (103, 2, 4, 100.0),# Beta to Delta
    (104, 3, 4, 80.0), # Gamma to Delta
    (105, 4, 1, 200.0) # Delta to Alpha
]
cursor.executemany('INSERT INTO routes VALUES (?, ?, ?, ?)', routes)

shipments = []
shipment_id = 1

def add_shipments(route_id, count):
    global shipment_id
    for _ in range(count):
        shipments.append((shipment_id, route_id, '2023-01-01 10:00:00'))
        shipment_id += 1

add_shipments(103, 50)
add_shipments(101, 20)
add_shipments(102, 15)
add_shipments(104, 10)
add_shipments(105, 5)

cursor.executemany('INSERT INTO shipments VALUES (?, ?, ?)', shipments)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
