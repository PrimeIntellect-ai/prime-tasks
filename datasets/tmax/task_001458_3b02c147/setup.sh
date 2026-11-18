#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make sqlite3
    pip3 install pytest

    mkdir -p /app/sqlite-backup-validator-1.0
    mkdir -p /home/user

    # Create the test DB generator
    cat << 'EOF' > /app/setup_test_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/backup.db')
c = conn.cursor()
c.execute('CREATE TABLE customers (customer_id INTEGER PRIMARY KEY, customer_name TEXT)')
c.execute('CREATE TABLE orders (order_id INTEGER PRIMARY KEY, customer_id INTEGER, amount REAL)')
c.execute('CREATE TABLE items (item_id INTEGER PRIMARY KEY, order_id INTEGER, item_name TEXT)')

random.seed(42)
for i in range(1, 101):
    c.execute('INSERT INTO customers VALUES (?, ?)', (i, f'Customer_{i}'))
    for _ in range(random.randint(1, 5)):
        order_id = random.randint(1000, 999999)
        c.execute('INSERT INTO orders VALUES (?, ?, ?)', (order_id, i, round(random.uniform(10.0, 100.0), 2)))
        for _ in range(random.randint(1, 10)):
            c.execute('INSERT INTO items (order_id, item_name) VALUES (?, ?)', (order_id, 'Item_X'))

conn.commit()
conn.close()
EOF

    # Create the vendored package files
    cat << 'EOF' > /app/sqlite-backup-validator-1.0/Makefile
validate:
	python3 validator.py --db /tmp/nowhere.db --out /home/user/validation_summary.json
EOF

    cat << 'EOF' > /app/sqlite-backup-validator-1.0/validator.py
import sqlite3
import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument('--db', required=True)
parser.add_argument('--out', required=True)
args = parser.parse_args()

conn = sqlite3.connect(args.db)
c = conn.cursor()

# BUG: Implicit cross join on items table
query = """
SELECT c.customer_id, c.customer_name, SUM(o.amount), COUNT(i.item_id)
FROM customers c, orders o, items i
WHERE c.customer_id = o.customer_id
GROUP BY c.customer_id
"""

c.execute(query)
rows = c.fetchall()

result = []
for row in rows:
    result.append({
        "customer_id": row[0],
        "customer_name": row[1],
        "total_order_amount": round(row[2], 2) if row[2] else 0.0,
        "total_items": row[3]
    })

with open(args.out, 'w') as f:
    json.dump(result, f, indent=2)
EOF

    chmod -R 755 /app/sqlite-backup-validator-1.0
    chmod 755 /app/setup_test_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
