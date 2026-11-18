#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

random.seed(42)

conn = sqlite3.connect('/home/user/ecommerce.db')
cursor = conn.cursor()

cursor.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, region TEXT)')
cursor.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT)')
cursor.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, user_id INTEGER, product_id INTEGER, amount REAL, tx_date TEXT)')

# Insert Users
users = [(i, f"User_{i}", random.choice(["North", "South", "East", "West"])) for i in range(1, 101)]
cursor.executemany('INSERT INTO users VALUES (?, ?, ?)', users)

# Insert Products
categories = ["Electronics", "Clothing", "Home", "Toys"]
products = [(i, f"Product_{i}", random.choice(categories)) for i in range(1, 51)]
# Guarantee some electronics
products[0] = (1, "Product_1", "Electronics")
products[1] = (2, "Product_2", "Electronics")
cursor.executemany('INSERT INTO products VALUES (?, ?, ?)', products)

# Insert Transactions
transactions = []
for i in range(1, 5001):
    u_id = random.randint(1, 100)
    p_id = random.randint(1, 50)
    amt = round(random.uniform(10.0, 500.0), 2)
    # Generate dates in 2023
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    date_str = f"2023-{month:02d}-{day:02d}"
    transactions.append((i, u_id, p_id, amt, date_str))

cursor.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?, ?)', transactions)

# Create a "bad" index
cursor.execute('CREATE INDEX idx_bad ON transactions(amount)')

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    chown -R user:user /home/user/ecommerce.db
    chmod -R 777 /home/user
