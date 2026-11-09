#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev espeak gcc
    pip3 install pytest

    mkdir -p /app

    # Create the SQLite database
    sqlite3 /app/backup.db <<EOF
CREATE TABLE products (product_id INTEGER PRIMARY KEY, category TEXT, price INTEGER);
CREATE TABLE orders (order_id INTEGER PRIMARY KEY, product_id INTEGER, quantity INTEGER);

INSERT INTO products VALUES (1, 'Electronics', 500);
INSERT INTO products VALUES (2, 'Electronics', 300);
INSERT INTO products VALUES (3, 'Clothing', 50);
INSERT INTO products VALUES (4, 'Clothing', 40);

INSERT INTO orders VALUES (101, 1, 2);
INSERT INTO orders VALUES (102, 1, 1);
INSERT INTO orders VALUES (103, 3, 5);
INSERT INTO orders VALUES (104, 4, 2);
INSERT INTO orders VALUES (105, 2, 3);
EOF

    # Create the audio file
    espeak -w /app/incident_report.wav "Incident 892. The revenue report query contains an implicit cross join between the orders and products tables, resulting in massively inflated revenue numbers. Fix the query by explicitly joining on product_id. The report must group by category and calculate total revenue as the sum of quantity times price."

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
