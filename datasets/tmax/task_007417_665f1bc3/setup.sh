#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
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

c.execute('''CREATE TABLE users (user_id INTEGER PRIMARY KEY, name TEXT, reg_year INTEGER)''')
c.execute('''CREATE TABLE orders (order_id INTEGER PRIMARY KEY, user_id INTEGER, total NUMERIC)''')
c.execute('''CREATE TABLE order_items (item_id INTEGER PRIMARY KEY, order_id INTEGER, category TEXT, price NUMERIC, quantity INTEGER)''')

# Users
users = [
    (1, 'Alice', 2022),
    (2, 'Bob', 2022),
    (3, 'Charlie', 2021),
    (4, 'Diana', 2022)
]
c.executemany("INSERT INTO users VALUES (?,?,?)", users)

# Orders
orders = [
    (101, 1, 150.00),
    (102, 2, 90.00),
    (103, 3, 200.00),
    (104, 4, 300.00),
    (105, 4, 105.00)
]
c.executemany("INSERT INTO orders VALUES (?,?,?)", orders)

# Order Items
items = [
    (1001, 101, 'Electronics', 50.00, 2),
    (1002, 101, 'Books', 20.00, 1),
    (1003, 102, 'Electronics', 90.00, 1),
    (1004, 103, 'Electronics', 200.00, 1),
    (1005, 104, 'Electronics', 150.00, 1),
    (1006, 104, 'Clothing', 50.00, 3),
    (1007, 105, 'Electronics', 10.00, 5)
]
c.executemany("INSERT INTO order_items VALUES (?,?,?,?,?)", items)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    chmod -R 777 /home/user
