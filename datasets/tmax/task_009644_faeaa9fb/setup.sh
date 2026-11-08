#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

random.seed(42)

conn = sqlite3.connect('/home/user/logistics.db')
c = conn.cursor()

c.execute("CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, order_date TEXT)")
c.execute("CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, price REAL)")
c.execute("CREATE TABLE shipments (id INTEGER PRIMARY KEY, order_id INTEGER, status TEXT, actual_delivery TEXT, expected_delivery TEXT)")

# Insert customers
for i in range(1, 101):
    c.execute("INSERT INTO customers VALUES (?, ?)", (i, f"Customer_{i}"))

# Insert orders, items, shipments
order_id = 1
item_id = 1
shipment_id = 1
for cust_id in range(1, 101):
    num_orders = random.randint(1, 10)
    for _ in range(num_orders):
        date = f"2023-10-{random.randint(10, 31)}"
        c.execute("INSERT INTO orders VALUES (?, ?, ?)", (order_id, cust_id, date))

        # items
        for _ in range(random.randint(1, 5)):
            c.execute("INSERT INTO order_items VALUES (?, ?, ?)", (item_id, order_id, round(random.uniform(10.0, 100.0), 2)))
            item_id += 1

        # shipments
        status = 'DELAYED' if random.random() < 0.2 else 'DELIVERED'
        c.execute("INSERT INTO shipments VALUES (?, ?, ?, NULL, NULL)", (shipment_id, order_id, status))
        shipment_id += 1

        order_id += 1

conn.commit()
conn.close()
EOF

python3 /tmp/setup_db.py
rm /tmp/setup_db.py

chmod -R 777 /home/user
