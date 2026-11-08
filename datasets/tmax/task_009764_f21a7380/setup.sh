#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/ecommerce.db')
c = conn.cursor()

c.executescript('''
CREATE TABLE customers (id INTEGER PRIMARY KEY, joined_date TEXT, country TEXT);
CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, order_date TEXT, total_amount REAL);
CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER, price REAL);
CREATE TABLE products (id INTEGER PRIMARY KEY, category TEXT, name TEXT);

INSERT INTO customers VALUES (1, '2023-01-15', 'US'), (2, '2023-01-20', 'UK'), (3, '2023-02-10', 'CA');
INSERT INTO orders VALUES (101, 1, '2023-01-16', 150.0), (102, 2, '2023-01-22', 300.0), (103, 3, '2023-02-11', 500.0), (104, 1, '2023-03-01', 200.0);
INSERT INTO products VALUES (10, 'Electronics', 'Phone'), (11, 'Apparel', 'Shirt'), (12, 'Books', 'Novel');

-- Order 101 (Cohort 2023-01, Total 150)
INSERT INTO order_items VALUES (1001, 101, 10, 1, 100.0), (1002, 101, 11, 2, 25.0);
-- Order 102 (Cohort 2023-01, Total 300)
INSERT INTO order_items VALUES (1003, 102, 10, 1, 200.0), (1004, 102, 12, 5, 20.0);
-- Order 104 (Cohort 2023-01, Total 200)
INSERT INTO order_items VALUES (1005, 104, 11, 4, 50.0);
-- Order 103 (Cohort 2023-02, Total 500)
INSERT INTO order_items VALUES (1006, 103, 10, 1, 400.0), (1007, 103, 12, 5, 20.0);
''')
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
