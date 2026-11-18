#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import sqlite3
import os

db_path = '/home/user/logistics.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE locations (id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE connections (id INTEGER PRIMARY KEY, loc1_id INTEGER, loc2_id INTEGER, distance_km INTEGER, active INTEGER)''')

locations = [
    (1, 'Alpha'),
    (2, 'Beta'),
    (3, 'Gamma'),
    (4, 'Delta'),
    (5, 'Omega')
]
c.executemany('INSERT INTO locations VALUES (?, ?)', locations)

# Graph edges
connections = [
    (1, 1, 2, 10, 1), # Alpha -> Beta (10)
    (2, 2, 3, 20, 1), # Beta -> Gamma (20)
    (3, 3, 5, 30, 1), # Gamma -> Omega (30)
    (4, 1, 4, 50, 1), # Alpha -> Delta (50)
    (5, 4, 5, 5, 1),  # Delta -> Omega (5)
    (6, 1, 5, 100, 1),# Alpha -> Omega (100)
    (7, 2, 4, 5, 0)   # Beta -> Delta (5, but inactive)
]
c.executemany('INSERT INTO connections VALUES (?, ?, ?, ?, ?)', connections)
conn.commit()
conn.close()

script_content = """import sqlite3
import json

def get_routes(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    # BUG: Implicit cross join returning N^2 rows with mismatched distances
    query = '''
    SELECT l1.name as source, l2.name as dest, c.distance_km
    FROM locations l1, locations l2, connections c
    WHERE c.active = 1
    '''
    cursor.execute(query)
    return cursor.fetchall()

def main():
    routes = get_routes('/home/user/logistics.db')

    # TODO: Implement shortest path from 'Alpha' to 'Omega'
    # TODO: Export to /home/user/shortest_path.json
    pass

if __name__ == "__main__":
    main()
"""

with open('/home/user/route_solver.py', 'w') as f:
    f.write(script_content)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
