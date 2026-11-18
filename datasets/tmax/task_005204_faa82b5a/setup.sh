#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /app
    git clone --branch v0.48.9 https://github.com/kayak/pypika.git /app/pypika
    echo "packages=find_packages(,,)" >> /app/pypika/setup.py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/ecommerce.db')
c = conn.cursor()
c.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, date TEXT)')
c.execute('CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, price REAL)')

c.executemany('INSERT INTO customers VALUES (?, ?)', ((i, f'Customer {i}') for i in range(1, 50001)))
c.executemany('INSERT INTO orders VALUES (?, ?, ?)', ((i, random.randint(1, 50000), '2023-01-01') for i in range(1, 150001)))
c.executemany('INSERT INTO order_items VALUES (?, ?, ?, ?)', ((i, random.randint(1, 150000), random.randint(1, 100), random.uniform(10.0, 100.0)) for i in range(1, 400001)))

conn.commit()
conn.close()
EOF

    python3 /home/user/generate_db.py
    rm /home/user/generate_db.py

    cat << 'EOF' > /home/user/report_generator.py
import sqlite3
import json
import time

def generate_report():
    # Placeholder pypika usage with deliberate cross_join
    # q = Query.from_(customers).join(orders).on(customers.id == orders.customer_id).cross_join(order_items)
    pass

if __name__ == '__main__':
    generate_report()
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app/pypika
