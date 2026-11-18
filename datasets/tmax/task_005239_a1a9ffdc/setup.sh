#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import random
import os

db_path = "/home/user/ecommerce.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create Schema
cursor.executescript("""
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT, price REAL);
CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER);
CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER);
""")

random.seed(42)

# Insert Data
users = [(i, f"User_{i}") for i in range(1, 1001)]
cursor.executemany("INSERT INTO users VALUES (?, ?)", users)

categories = ["Electronics", "Clothing", "Home", "Toys", "Books"]
products = [(i, f"Product_{i}", random.choice(categories), round(random.uniform(10.0, 500.0), 2)) for i in range(1, 201)]
cursor.executemany("INSERT INTO products VALUES (?, ?, ?, ?)", products)

orders = [(i, random.randint(1, 1000)) for i in range(1, 5001)]
cursor.executemany("INSERT INTO orders VALUES (?, ?)", orders)

order_items = [(i, random.randint(1, 5000), random.randint(1, 200), random.randint(1, 5)) for i in range(1, 15001)]
cursor.executemany("INSERT INTO order_items VALUES (?, ?, ?, ?)", order_items)

conn.commit()
conn.close()

# Create initial slow script
script_content = """import sqlite3
import sys
import json

def generate_report(category):
    conn = sqlite3.connect('/home/user/ecommerce.db')
    cursor = conn.cursor()

    # Inefficient query with correlated subquery
    query = '''
    SELECT u.id, u.name,
           (SELECT SUM(oi.quantity * p.price)
            FROM orders o
            JOIN order_items oi ON o.id = oi.order_id
            JOIN products p ON oi.product_id = p.id
            WHERE o.user_id = u.id AND p.category = ?) as total_spend
    FROM users u
    WHERE total_spend > 0
    ORDER BY total_spend DESC
    LIMIT 5;
    '''

    cursor.execute(query, (category,))
    results = cursor.fetchall()

    output = [{"user_id": row[0], "name": row[1], "total_spend": round(row[2], 2)} for row in results]

    with open('/home/user/report.json', 'w') as f:
        json.dump(output, f, indent=4)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python generate_report.py <category>")
        sys.exit(1)
    generate_report(sys.argv[1])
"""

with open("/home/user/generate_report.py", "w") as f:
    f.write(script_content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py
    chmod -R 777 /home/user
