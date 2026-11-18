#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/company.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
cursor.execute('''
CREATE TABLE customers (
    id INTEGER PRIMARY KEY,
    name TEXT,
    region TEXT
)
''')

cursor.execute('''
CREATE TABLE products (
    id INTEGER PRIMARY KEY,
    name TEXT,
    category TEXT
)
''')

cursor.execute('''
CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    customer_id INTEGER,
    order_date TEXT,
    FOREIGN KEY(customer_id) REFERENCES customers(id)
)
''')

cursor.execute('''
CREATE TABLE order_items (
    id INTEGER PRIMARY KEY,
    order_id INTEGER,
    product_id INTEGER,
    quantity INTEGER,
    price REAL,
    FOREIGN KEY(order_id) REFERENCES orders(id),
    FOREIGN KEY(product_id) REFERENCES products(id)
)
''')

# Insert data
cursor.executemany('INSERT INTO customers VALUES (?, ?, ?)', [
    (1, 'Alice', 'North'),
    (2, 'Bob', 'South'),
    (3, 'Charlie', 'North'),
    (4, 'Diana', 'East'),
    (5, 'Evan', 'West')
])

cursor.executemany('INSERT INTO products VALUES (?, ?, ?)', [
    (1, 'Laptop', 'Electronics'),
    (2, 'Mouse', 'Electronics'),
    (3, 'Desk', 'Furniture'),
    (4, 'Monitor', 'Electronics')
])

cursor.executemany('INSERT INTO orders VALUES (?, ?, ?)', [
    (1, 1, '2023-01-01'),
    (2, 2, '2023-01-02'),
    (3, 3, '2023-01-03'),
    (4, 4, '2023-01-04'),
    (5, 5, '2023-01-05'),
    (6, 1, '2023-01-06')
])

cursor.executemany('INSERT INTO order_items VALUES (?, ?, ?, ?, ?)', [
    (1, 1, 1, 1, 1000.0),
    (2, 1, 2, 2, 50.0),
    (3, 2, 1, 2, 1000.0),
    (4, 3, 3, 1, 200.0),
    (5, 4, 4, 3, 300.0),
    (6, 5, 2, 1, 50.0),
    (7, 6, 1, 1, 1000.0)
])

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
