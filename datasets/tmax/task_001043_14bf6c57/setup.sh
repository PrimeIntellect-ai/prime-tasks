#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib pydantic jsonschema

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('bom.db')
cursor = conn.cursor()

cursor.execute('CREATE TABLE components (part_id TEXT PRIMARY KEY, name TEXT, category TEXT)')
cursor.execute('CREATE TABLE assembly (parent_id TEXT, child_id TEXT)')
cursor.execute('CREATE INDEX idx_assembly_parent ON assembly(parent_id)')

components = [
    ('PROD-001', 'Super Widget', 'Product'),
    ('SUB-010', 'Motor Assembly', 'Subassembly'),
    ('SUB-020', 'Casing Assembly', 'Subassembly'),
    ('PART-100', 'Screws', 'Fastener'),
    ('PART-200', 'DC Motor', 'Electrical'),
    ('PART-300', 'Plastic Shell', 'Housing'),
    ('PART-400', 'Rubber Feet', 'Accessory'),
    ('UNUSED-99', 'Old Gear', 'Mechanical')
]

assembly = [
    ('PROD-001', 'SUB-010'),
    ('PROD-001', 'SUB-020'),
    ('PROD-001', 'PART-400'),
    ('SUB-010', 'PART-100'),
    ('SUB-010', 'PART-200'),
    ('SUB-020', 'PART-100'),
    ('SUB-020', 'PART-300')
]

cursor.executemany('INSERT INTO components VALUES (?, ?, ?)', components)
cursor.executemany('INSERT INTO assembly VALUES (?, ?)', assembly)

conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
