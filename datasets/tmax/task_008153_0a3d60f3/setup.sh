#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)
db_path = '/home/user/ecommerce.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('''CREATE TABLE sales (transaction_id INTEGER PRIMARY KEY, product_id TEXT, sale_date DATE, amount REAL)''')
cur.execute('''CREATE TABLE product_graph (src_product_id TEXT, dst_product_id TEXT, relationship_type TEXT)''')

graph_data = [
    ('A1', 'B1', 'is_accessory_of'),
    ('A2', 'B1', 'is_accessory_of'),
    ('A3', 'B2', 'is_accessory_of'),
    ('B1', 'C1', 'upgrades_to')
]
cur.executemany("INSERT INTO product_graph VALUES (?, ?, ?)", graph_data)

sales_data = [
    (1, 'A1', '2023-10-01', 10.0),
    (2, 'A1', '2023-10-01', 15.0),
    (3, 'A1', '2023-10-02', 20.0),
    (4, 'A1', '2023-10-03', 30.0),
    (5, 'A1', '2023-10-04', 10.0),
    (6, 'A2', '2023-10-01', 50.0),
    (7, 'A2', '2023-10-03', 60.0),
    (8, 'A3', '2023-10-01', 100.0),
    (9, 'B1', '2023-10-01', 500.0)
]
cur.executemany("INSERT INTO sales VALUES (?, ?, ?, ?)", sales_data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py

    chmod -R 777 /home/user
