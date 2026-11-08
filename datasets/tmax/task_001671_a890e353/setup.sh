#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3

conn = sqlite3.connect('/home/user/store.db')
c = conn.cursor()

c.execute('''CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, status TEXT)''')
c.execute('''CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT)''')
c.execute('''CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, product_id INTEGER, amount REAL)''')

users = [(1, 'Alice', 'active'), (2, 'Bob', 'active'), (3, 'Charlie', 'inactive')]
c.executemany("INSERT INTO users VALUES (?, ?, ?)", users)

products = [(1, 'Laptop', 'electronics'), (2, 'Mouse', 'electronics'), (3, 'Book', 'books')]
c.executemany("INSERT INTO products VALUES (?, ?, ?)", products)

orders = [
    (1, 1, 1, 1000.0), # Alice, Laptop
    (2, 1, 2, 50.0),   # Alice, Mouse
    (3, 2, 3, 20.0),   # Bob, Book
    (4, 2, 1, 1000.0), # Bob, Laptop
    (5, 3, 1, 1000.0)  # Charlie, Laptop
]
c.executemany("INSERT INTO orders VALUES (?, ?, ?, ?)", orders)

conn.commit()
conn.close()

with open('/home/user/analyze.py', 'w') as f:
    f.write('''import sqlite3
import csv

conn = sqlite3.connect('/home/user/store.db')
c = conn.cursor()

# BUG: Implicit cross join between orders and products
query = """
SELECT u.name, SUM(o.amount)
FROM users u, orders o, products p
WHERE u.id = o.user_id 
  AND p.category = 'electronics' 
  AND u.status = 'active'
GROUP BY u.name;
"""

c.execute(query)
results = c.fetchall()

with open('/home/user/results.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['name', 'total_spent'])
    writer.writerows(results)

conn.close()
''')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
