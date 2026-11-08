#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++ wget
    pip3 install pytest

    mkdir -p /home/user/db_perf
    cd /home/user/db_perf

    cat << 'EOF' > /home/user/db_perf/setup_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/db_perf/sales.db')
c = conn.cursor()

c.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, region TEXT)")
c.execute("CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, order_date TEXT, status TEXT)")
c.execute("CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT)")
c.execute("CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER, price REAL)")

regions = ['North', 'South', 'East', 'West']
categories = ['Electronics', 'Clothing', 'Home', 'Toys']
statuses = ['COMPLETED', 'PENDING', 'CANCELLED']

# Insert users
users = []
for i in range(1, 101):
    r = regions[i % 4]
    users.append((i, f"User_{i}", r))
c.executemany("INSERT INTO users VALUES (?, ?, ?)", users)

# Insert products
products = []
for i in range(1, 51):
    cat = categories[i % 4]
    products.append((i, f"Product_{i}", cat))
c.executemany("INSERT INTO products VALUES (?, ?, ?)", products)

# Insert orders and items
random.seed(42)
order_items = []
orders = []
item_id = 1
for i in range(1, 1001):
    u_id = random.randint(1, 100)
    status = random.choice(statuses)
    orders.append((i, u_id, f"2023-01-{random.randint(1,28):02d}", status))

    # 1 to 3 items per order
    for _ in range(random.randint(1, 3)):
        p_id = random.randint(1, 50)
        qty = random.randint(1, 5)
        price = round(random.uniform(10.0, 100.0), 2)
        order_items.append((item_id, i, p_id, qty, price))
        item_id += 1

c.executemany("INSERT INTO orders VALUES (?, ?, ?, ?)", orders)
c.executemany("INSERT INTO order_items VALUES (?, ?, ?, ?, ?)", order_items)

conn.commit()
conn.close()
EOF

    python3 /home/user/db_perf/setup_db.py
    chmod 666 /home/user/db_perf/sales.db

    cat << 'EOF' > /home/user/verify.py
import json
import sqlite3
import sys

def verify():
    # Check if indexes were created
    conn = sqlite3.connect('/home/user/db_perf/sales.db')
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='index'")
    indexes = [row[0] for row in c.fetchall() if not row[0].startswith('sqlite_')]
    if not indexes:
        print("Verification failed: No custom indexes found in database.")
        sys.exit(1)

    # Calculate truth
    c.execute("""
        SELECT u.region, p.category, SUM(oi.quantity * oi.price), COUNT(DISTINCT o.id)
        FROM users u
        JOIN orders o ON u.id = o.user_id
        JOIN order_items oi ON o.id = oi.order_id
        JOIN products p ON oi.product_id = p.id
        WHERE o.status = 'COMPLETED'
        GROUP BY u.region, p.category
    """)
    truth_data = {}
    for region, category, rev, count in c.fetchall():
        if region not in truth_data:
            truth_data[region] = {}
        truth_data[region][category] = {"revenue": round(rev, 2), "order_count": count}

    # Load agent JSON
    try:
        with open('/home/user/db_perf/regional_summary.json', 'r') as f:
            agent_data = json.load(f)
    except Exception as e:
        print(f"Verification failed: Could not read JSON ({e})")
        sys.exit(1)

    # Compare structure and values
    for region_obj in agent_data:
        r = region_obj.get("region")
        if r not in truth_data:
            print(f"Verification failed: Unexpected region {r} in output.")
            sys.exit(1)

        for cat_obj in region_obj.get("categories", []):
            c_name = cat_obj.get("category")
            if c_name not in truth_data[r]:
                print(f"Verification failed: Unexpected category {c_name} in region {r}.")
                sys.exit(1)

            # Check revenue with small float tolerance
            truth_rev = truth_data[r][c_name]["revenue"]
            agent_rev = cat_obj.get("revenue", 0)
            if abs(truth_rev - agent_rev) > 0.1:
                print(f"Verification failed: Revenue mismatch for {r}-{c_name}. Expected {truth_rev}, got {agent_rev}")
                sys.exit(1)

            truth_cnt = truth_data[r][c_name]["order_count"]
            agent_cnt = cat_obj.get("order_count", 0)
            if truth_cnt != agent_cnt:
                print(f"Verification failed: Order count mismatch for {r}-{c_name}. Expected {truth_cnt}, got {agent_cnt}")
                sys.exit(1)

    print("Verification passed.")
    sys.exit(0)

if __name__ == "__main__":
    verify()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
