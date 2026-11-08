#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gnupg curl
    pip3 install pytest

    # Install MongoDB
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update && apt-get install -y mongodb-org

    # Create user
    useradd -m -s /bin/bash user || true

    # Create SQLite database
    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)
db_path = '/home/user/sales.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, region TEXT)")
c.execute("CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, order_date TEXT)")
c.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, order_id INTEGER, product TEXT, price REAL, quantity INTEGER)")

customers = [
    (1, 'Alice', 'North'),
    (2, 'Bob', 'South'),
    (3, 'Charlie', 'East'),
    (4, 'Diana', 'West'),
    (5, 'Eve', 'North')
]
c.executemany("INSERT INTO customers VALUES (?, ?, ?)", customers)

orders = [
    (101, 1, '2023-01-15'),
    (102, 1, '2023-02-10'),
    (103, 2, '2023-01-20'),
    (104, 3, '2023-03-05'),
    (105, 4, '2023-03-10'),
    (106, 5, '2023-04-01')
]
c.executemany("INSERT INTO orders VALUES (?, ?, ?)", orders)

items = [
    (1001, 101, 'Widget', 10.0, 5),
    (1002, 101, 'Gadget', 25.0, 2),
    (1003, 102, 'Widget', 10.0, 10),
    (1004, 103, 'Thing', 5.0, 20),
    (1005, 103, 'Gadget', 25.0, 6),
    (1006, 104, 'SuperWidget', 50.0, 10),
    (1007, 105, 'Thing', 5.0, 50),
    (1008, 106, 'Widget', 10.0, 1)
]
c.executemany("INSERT INTO items VALUES (?, ?, ?, ?, ?)", items)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup.py

    # Set permissions
    chmod -R 777 /home/user
