#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)
db_path = '/home/user/data.db'

if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT, category TEXT)')
c.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, cust_id INTEGER, item_id INTEGER, tx_date TEXT)')
c.execute('CREATE TABLE feedbacks (id INTEGER PRIMARY KEY, cust_id INTEGER, item_id INTEGER, rating INTEGER)')

c.executemany('INSERT INTO customers VALUES (?,?)', [
    (1, 'Alice'), 
    (2, 'Bob'), 
    (3, 'Charlie'), 
    (4, 'Diana'), 
    (5, 'Eve')
])

c.executemany('INSERT INTO items VALUES (?,?,?)', [
    (101, 'Laptop', 'Tech'), 
    (102, 'Mouse', 'Tech'), 
    (103, 'Keyboard', 'Tech'), 
    (104, 'Monitor', 'Tech')
])

c.executemany('INSERT INTO transactions VALUES (?,?,?,?)', [
    (1, 1, 101, '2023-01-01'), 
    (2, 2, 101, '2023-01-02'), 
    (3, 3, 102, '2023-01-03'), 
    (4, 5, 104, '2023-01-04'), 
    (5, 4, 102, '2023-01-05')  
])

c.executemany('INSERT INTO feedbacks VALUES (?,?,?,?)', [
    (1, 2, 101, 5), 
    (2, 1, 103, 1), 
    (3, 3, 102, 5), 
    (4, 5, 101, 5), 
    (5, 5, 104, 1), 
    (6, 4, 104, 1)  
])

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
