#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user
    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('ecommerce.db')
cursor = conn.cursor()

cursor.executescript('''
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT,
    email TEXT
);

CREATE TABLE products (
    id INTEGER PRIMARY KEY,
    name TEXT,
    category TEXT,
    price REAL
);

CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    user_id INTEGER,
    order_date TEXT
);

CREATE TABLE order_items (
    id INTEGER PRIMARY KEY,
    order_id INTEGER,
    product_id INTEGER,
    quantity INTEGER
);
''')

# Insert data
users = [
    (1, 'Alice Smith', 'alice@example.com'),
    (2, 'Bob Jones', 'bob@example.com'),
    (3, 'Charlie Brown', 'charlie@example.com')
]
cursor.executemany('INSERT INTO users VALUES (?, ?, ?)', users)

products = [
    (1, 'Laptop', 'Electronics', 999.99),
    (2, 'Smartphone', 'Electronics', 599.99),
    (3, 'Novel', 'Books', 14.99),
    (4, 'T-Shirt', 'Clothing', 19.99),
    (5, 'Headphones', 'Electronics', 149.99)
]
cursor.executemany('INSERT INTO products VALUES (?, ?, ?, ?)', products)

orders = [
    (1, 1, '2023-05-14'),
    (2, 2, '2023-08-22'),
    (3, 1, '2022-11-05'),
    (4, 3, '2023-12-01'),
    (5, 2, '2023-01-15')
]
cursor.executemany('INSERT INTO orders VALUES (?, ?, ?)', orders)

order_items = [
    (1, 1, 1, 1),
    (2, 1, 5, 2),
    (3, 2, 2, 1),
    (4, 3, 3, 5),
    (5, 4, 1, 2),
    (6, 4, 4, 3),
    (7, 5, 5, 1)
]
cursor.executemany('INSERT INTO order_items VALUES (?, ?, ?, ?)', order_items)

conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    chmod -R 777 /home/user
