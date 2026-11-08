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

db_path = "/home/user/store.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE customers (
    id INTEGER PRIMARY KEY,
    name TEXT,
    email TEXT
)''')

c.execute('''CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    customer_id INTEGER,
    status TEXT,
    total REAL,
    created_at TEXT,
    FOREIGN KEY(customer_id) REFERENCES customers(id)
)''')

random.seed(42)

# Insert customers
for i in range(1, 101):
    c.execute("INSERT INTO customers (id, name, email) VALUES (?, ?, ?)", 
              (i, f"Customer {i}", f"customer{i}@example.com"))

# Insert orders
statuses = ['pending', 'shipped', 'delivered', 'cancelled']
start_date = datetime.datetime(2023, 1, 1)

for i in range(1, 2001):
    cust_id = random.randint(1, 100)
    status = random.choice(statuses)
    total = round(random.uniform(10.0, 500.0), 2)
    delta = datetime.timedelta(minutes=random.randint(1, 500000))
    created_at = (start_date + delta).strftime("%Y-%m-%d %H:%M:%S")
    c.execute("INSERT INTO orders (id, customer_id, status, total, created_at) VALUES (?, ?, ?, ?, ?)",
              (i, cust_id, status, total, created_at))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
