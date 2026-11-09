#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the database setup script
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/logistics.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
cursor.execute('''CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, segment TEXT)''')
cursor.execute('''CREATE TABLE categories (id INTEGER PRIMARY KEY, category_name TEXT)''')
cursor.execute('''CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category_id INTEGER)''')
cursor.execute('''CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, order_date TEXT)''')
cursor.execute('''CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER, unit_price REAL)''')

# Insert data
customers = [
    (1, 'Alice', 'Retail'), (2, 'Bob', 'Enterprise'), (3, 'Charlie', 'Retail'),
    (4, 'Diana', 'Enterprise'), (5, 'Eve', 'Retail'), (6, 'Frank', 'Enterprise')
]
categories = [(1, 'Electronics'), (2, 'Books'), (3, 'Clothing'), (4, 'Home')]
products = [
    (1, 'Laptop', 1), (2, 'Phone', 1), (3, 'Novel', 2), (4, 'Textbook', 2),
    (5, 'Shirt', 3), (6, 'Pants', 3), (7, 'Desk', 4), (8, 'Chair', 4)
]
orders = [
    (1, 2, '2023-01-01'), (2, 2, '2023-01-05'), (3, 4, '2023-01-10'),
    (4, 6, '2023-01-15'), (5, 1, '2023-01-20'), (6, 3, '2023-01-25'),
    (7, 5, '2023-01-30')
]
order_items = [
    (1, 1, 1, 2, 1000.0), # order 1, Laptop, qty 2, price 1000 -> 2000
    (2, 1, 2, 1, 500.0),  # order 1, Phone, qty 1, price 500 -> 500
    (3, 2, 7, 5, 200.0),  # order 2, Desk, qty 5, price 200 -> 1000
    (4, 3, 4, 10, 50.0),  # order 3, Textbook, qty 10, price 50 -> 500
    (5, 3, 5, 20, 20.0),  # order 3, Shirt, qty 20, price 20 -> 400
    (6, 4, 1, 1, 1000.0), # order 4, Laptop, qty 1, price 1000 -> 1000
    (7, 5, 8, 5, 200.0),  # order 5, Chair, qty 5, price 200 -> 1000
    (8, 6, 3, 2, 50.0),   # order 6, Novel, qty 2, price 50 -> 100
    (9, 7, 6, 1, 20.0),   # order 7, Pants, qty 1, price 20 -> 20
]

cursor.executemany('INSERT INTO customers VALUES (?, ?, ?)', customers)
cursor.executemany('INSERT INTO categories VALUES (?, ?)', categories)
cursor.executemany('INSERT INTO products VALUES (?, ?, ?)', products)
cursor.executemany('INSERT INTO orders VALUES (?, ?, ?)', orders)
cursor.executemany('INSERT INTO order_items VALUES (?, ?, ?, ?, ?)', order_items)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
