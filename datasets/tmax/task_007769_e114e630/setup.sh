#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random
import datetime

db_path = '/home/user/ecommerce.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)')
cursor.execute('CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, amount REAL, order_date DATE)')

names = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Heidi", "Ivan", "Judy"]
for i, name in enumerate(names, 1):
    cursor.execute('INSERT INTO customers (id, name) VALUES (?, ?)', (i, name))

random.seed(42)
start_date = datetime.date(2023, 1, 1)
for i in range(1, 1001):
    c_id = random.randint(1, 10)
    amount = round(random.uniform(10.0, 500.0), 2)
    o_date = start_date + datetime.timedelta(days=random.randint(0, 365))
    cursor.execute('INSERT INTO orders (customer_id, amount, order_date) VALUES (?, ?, ?)', (c_id, amount, o_date.isoformat()))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
