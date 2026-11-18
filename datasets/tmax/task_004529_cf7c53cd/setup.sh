#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    mkdir -p /home/user
    cd /home/user

    # Create SQLite database
    cat << 'EOF' > create_db.py
import sqlite3

conn = sqlite3.connect('supply_chain.db')
c = conn.cursor()
c.execute('''CREATE TABLE components (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER, required_qty INTEGER, unit_cost REAL)''')

c.execute("INSERT INTO components VALUES (1, 'Hyperdrive', NULL, 1, 0.0)")
c.execute("INSERT INTO components VALUES (2, 'Core', 1, 1, 100.0)")
c.execute("INSERT INTO components VALUES (3, 'Shield', 1, 2, 50.0)")
c.execute("INSERT INTO components VALUES (4, 'Crystal', 2, 4, 10.0)")
c.execute("INSERT INTO components VALUES (5, 'Casing', 3, 1, 20.0)")
c.execute("INSERT INTO components VALUES (6, 'Screws', 2, 10, 0.5)")
c.execute("INSERT INTO components VALUES (7, 'Wiring', 2, 5, 2.0)")
c.execute("INSERT INTO components VALUES (8, 'Wiring_Shield', 3, 5, 2.0)")

conn.commit()
conn.close()
EOF

    python3 create_db.py
    rm create_db.py

    # Create JSON file
    cat << 'EOF' > suppliers.json
[
  {
    "supplier_id": "S1",
    "inventory": [
      {"component_id": 1, "qty": 5},
      {"component_id": 2, "qty": 10}
    ]
  },
  {
    "supplier_id": "S2",
    "inventory": [
      {"component_id": 2, "qty": 15},
      {"component_id": 4, "qty": 100}
    ]
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
