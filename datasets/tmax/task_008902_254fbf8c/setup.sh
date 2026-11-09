#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import sqlite3
import json
import os
from datetime import datetime, timedelta

os.makedirs('/home/user', exist_ok=True)

db_path = '/home/user/financial.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE addresses (id INTEGER PRIMARY KEY, address_text TEXT)''')
c.execute('''CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT, address_id INTEGER)''')
c.execute('''CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, amount REAL, timestamp DATETIME)''')

addresses = [(1, '123 Main St'), (2, '456 Oak Ave'), (3, '789 Pine Rd')]
accounts = [
    (101, 'Alice', 1),
    (102, 'Bob', 2),
    (103, 'Charlie', 1),
    (104, 'Dave', 3),
    (105, 'Eve', 1)
]
c.executemany('INSERT INTO addresses VALUES (?, ?)', addresses)
c.executemany('INSERT INTO accounts VALUES (?, ?, ?)', accounts)

base_time = datetime(2023, 1, 1, 12, 0, 0)

transactions = [
    (1, 101, 102, 15000.0, base_time),
    (2, 102, 103, 500.0, base_time + timedelta(hours=1)),
    (3, 104, 102, 5000.0, base_time),
    (4, 104, 101, 12000.0, base_time),
    (5, 101, 102, 100.0, base_time + timedelta(hours=1)),
    (6, 101, 104, 20000.0, base_time + timedelta(hours=2)),
    (7, 104, 105, 1000.0, base_time + timedelta(hours=3))
]
c.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?, ?)', transactions)
conn.commit()
conn.close()

entities = [
    {'account_id': 101, 'high_risk': True, 'business_type': 'retail'},
    {'account_id': 102, 'high_risk': True, 'business_type': 'shell'},
    {'account_id': 103, 'high_risk': False, 'business_type': 'retail'},
    {'account_id': 104, 'high_risk': False, 'business_type': 'consulting'},
    {'account_id': 105, 'high_risk': False, 'business_type': 'shell'}
]
with open('/home/user/entities.json', 'w') as f:
    json.dump(entities, f)
"

    chmod -R 777 /home/user
