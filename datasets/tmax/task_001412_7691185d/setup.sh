#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/ecommerce.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, email TEXT)''')
cursor.execute('''CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, order_date TEXT, status TEXT)''')
cursor.execute('''CREATE TABLE items (id INTEGER PRIMARY KEY, order_id INTEGER, product_name TEXT, price REAL)''')

# Insert data
customers = [
    (1, "Alice Smith", "alice@example.com"),
    (2, "Bob Jones", "bob@example.com"),
    (3, "Charlie Brown", "charlie@example.com"),
    (4, "Diana Prince", "diana@example.com") # No completed orders
]
cursor.executemany("INSERT INTO customers VALUES (?, ?, ?)", customers)

orders = [
    (101, 1, "2023-10-01", "completed"),
    (102, 1, "2023-10-05", "pending"),
    (103, 2, "2023-10-02", "completed"),
    (104, 3, "2023-10-03", "completed"),
    (105, 3, "2023-10-04", "completed"),
    (106, 4, "2023-10-06", "cancelled")
]
cursor.executemany("INSERT INTO orders VALUES (?, ?, ?, ?)", orders)

items = [
    (1001, 101, "Wireless Mouse", 25.50),
    (1002, 101, "Mechanical Keyboard", 125.00),
    (1003, 102, "Monitor", 300.00), # Belongs to pending order
    (1004, 103, "USB-C Cable", 15.00),
    (1005, 104, "Desk Lamp", 45.00),
    (1006, 105, "Notebook", 5.00),
    (1007, 105, "Pen Set", 12.00),
    (1008, 106, "Webcam", 60.00) # Belongs to cancelled order
]
cursor.executemany("INSERT INTO items VALUES (?, ?, ?, ?)", items)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
