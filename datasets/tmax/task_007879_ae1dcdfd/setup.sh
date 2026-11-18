#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/etl
    cd /home/user/etl

    # Create SQLite DB
    sqlite3 source.db <<EOF
CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, region TEXT);
CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, amount REAL, date TEXT);

INSERT INTO customers VALUES (1, 'Alice', 'North');
INSERT INTO customers VALUES (2, 'Bob', 'South');
INSERT INTO customers VALUES (3, 'Charlie', 'East');
INSERT INTO customers VALUES (4, 'Diana', 'North');

INSERT INTO orders VALUES (101, 1, 50.0, '2023-10-01');
INSERT INTO orders VALUES (102, 1, 25.5, '2023-10-01');
INSERT INTO orders VALUES (103, 2, 200.0, '2023-10-01');
INSERT INTO orders VALUES (104, 3, 100.0, '2023-10-02');
INSERT INTO orders VALUES (105, 4, 75.0, '2023-10-01');
EOF

    # Create buggy Python script
    cat << 'EOF' > migrate.py
import sqlite3
import json
import sys

date_filter = sys.argv[1]
conn = sqlite3.connect('source.db')
cursor = conn.cursor()

# BUG: Implicit cross join and string formatting (SQL injection risk / no parameterization)
query = f"SELECT customers.id, customers.name, customers.region, orders.id, orders.amount FROM customers, orders WHERE orders.date = '{date_filter}'"
cursor.execute(query)

rows = cursor.fetchall()
# BUG: Bad mapping, outputs flat cross product instead of nested documents
with open('output.jsonl', 'w') as f:
    for row in rows:
        doc = {
            "customer_id": row[0],
            "name": row[1],
            "region": row[2],
            "order_id": row[3],
            "amount": row[4]
        }
        f.write(json.dumps(doc) + "\n")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
