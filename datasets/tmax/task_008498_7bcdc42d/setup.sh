#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

db_path = '/home/user/ecommerce.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.executescript('''
CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, region TEXT);
CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, order_date TEXT);
CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER, price REAL);
CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT);

INSERT INTO customers VALUES 
(1, 'Alice', 'North America'),
(2, 'Bob', 'North America'),
(3, 'Charlie', 'North America'),
(4, 'Diana', 'Europe');

INSERT INTO products VALUES 
(1, 'Laptop', 'Electronics'),
(2, 'Mouse', 'Electronics'),
(3, 'Desk', 'Furniture'),
(4, 'Chair', 'Furniture');

INSERT INTO orders VALUES 
(1, 1, '2023-01-01'),
(2, 2, '2023-01-02'),
(3, 3, '2023-01-03'),
(4, 1, '2023-01-04');

INSERT INTO order_items VALUES 
(1, 1, 1, 1, 1000.0),
(2, 1, 2, 2, 50.0),
(3, 2, 3, 1, 300.0),
(4, 3, 4, 4, 50.0),
(5, 4, 1, 1, 1200.0),
(6, 4, 4, 1, 150.0);
''')

conn.commit()
conn.close()

script_content = '''import sqlite3
import json

def get_data():
    conn = sqlite3.connect('/home/user/ecommerce.db')
    c = conn.cursor()

    # BUG: Missing ON condition for products table
    query = """
    SELECT c.name, p.category, SUM(oi.quantity * oi.price) as total_revenue
    FROM customers c
    JOIN orders o ON c.id = o.customer_id
    JOIN order_items oi ON o.id = oi.order_id
    JOIN products p
    WHERE c.region = 'North America'
    GROUP BY c.name, p.category
    """

    c.execute(query)
    results = c.fetchall()
    conn.close()
    return results

if __name__ == "__main__":
    data = get_data()
    # TODO: Output to json
'''

with open('/home/user/generate_report.py', 'w') as f:
    f.write(script_content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
