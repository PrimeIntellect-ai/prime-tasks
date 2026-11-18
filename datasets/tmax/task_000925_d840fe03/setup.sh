#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/ecommerce.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE users (user_id INTEGER, name TEXT)")
c.execute("CREATE TABLE products (product_id INTEGER, category TEXT)")
c.execute("CREATE TABLE purchases (user_id INTEGER, product_id INTEGER, purchase_date TEXT)")

# Users 1 to 5
users = [(1, 'Alice'), (2, 'Bob'), (3, 'Charlie'), (4, 'Dave'), (5, 'Eve')]
c.executemany("INSERT INTO users VALUES (?, ?)", users)

# Products 101 to 106
products = [
    (101, 'Electronics'),
    (102, 'Electronics'),
    (103, 'Electronics'),
    (104, 'Clothing'),
    (105, 'Electronics'),
    (106, 'Electronics')
]
c.executemany("INSERT INTO products VALUES (?, ?)", products)

# Purchases
purchases = [
    (1, 101, '2023-05-01'),
    (1, 102, '2023-06-01'),
    (1, 103, '2023-07-01'),
    (1, 104, '2023-08-01'), # Clothing, should be ignored
    (1, 105, '2022-12-01'), # Old, should be ignored

    (2, 101, '2023-05-15'),
    (2, 102, '2023-06-15'),
    (2, 103, '2023-07-15'),
    (2, 106, '2023-08-15'),

    (3, 101, '2023-05-20'),
    (3, 102, '2023-06-20'),

    (4, 106, '2023-08-20'),
    (4, 103, '2023-07-20'),

    (5, 104, '2023-08-01')  # Clothing, ignored
]
c.executemany("INSERT INTO purchases VALUES (?, ?, ?)", purchases)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
