#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    # Create the SQLite database and populate it with problematic data
    sqlite3 catalog.db <<EOF
CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, metadata TEXT, status TEXT);
INSERT INTO products (id, name, metadata, status) VALUES (1, 'Widget A', '{"weight": 10, "color": "red"}', 'active');
-- Serialization anomaly: stored as Python dictionary string instead of valid JSON
INSERT INTO products (id, name, metadata, status) VALUES (2, 'Widget B', '{''weight'': 15, ''color'': ''blue''}', 'active');
-- Corrupted JSON and incorrect status that should be filtered
INSERT INTO products (id, name, metadata, status) VALUES (3, 'Widget C', '{"weight": 20, "color": "green', 'deleted');
EOF

    # Create the buggy Python script
    cat << 'EOF' > generate_catalog.py
import sqlite3
import json

def build():
    conn = sqlite3.connect('/home/user/catalog.db')
    c = conn.cursor()

    # Bug: Not filtering by status
    c.execute("SELECT id, name, metadata FROM products")

    catalog = []
    for row in c.fetchall():
        # Bug: Will fail on Python repr strings or corrupted json
        meta = json.loads(row[2])
        catalog.append({"id": row[0], "name": row[1], "meta": meta})

    with open('/home/user/catalog_output.json', 'w') as f:
        json.dump(catalog, f, indent=2)

if __name__ == '__main__':
    build()
EOF

    chmod -R 777 /home/user
