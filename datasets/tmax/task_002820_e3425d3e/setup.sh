#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential curl wget
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/ecommerce.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, region TEXT)')
c.execute('CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, total REAL)')
c.execute('CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_name TEXT)')

customers = [
    (1, 'Alice', 'Europe'),
    (2, 'Bob', 'North America'),
    (3, 'Charlie', 'Europe'),
    (4, 'David', 'Europe'),
    (5, 'Eve', 'Europe'),
    (6, 'Frank', 'Europe')
]

orders = [
    (101, 1, 50.0),
    (102, 3, 20.0),
    (103, 4, 150.0),
    (104, 4, 30.0),
    (105, 5, 200.0)
]

items = [
    (1001, 101, 'Book'),
    (1002, 102, 'Pen'),
    (1003, 103, 'Monitor'),
    (1004, 103, 'Keyboard'),
    (1005, 104, 'Mousepad'),
    (1006, 105, 'Desk')
]

c.executemany('INSERT INTO customers VALUES (?, ?, ?)', customers)
c.executemany('INSERT INTO orders VALUES (?, ?, ?)', orders)
c.executemany('INSERT INTO order_items VALUES (?, ?, ?)', items)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
