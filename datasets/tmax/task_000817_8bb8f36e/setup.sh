#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang
    pip3 install pytest

    mkdir -p /home/user
    sqlite3 /home/user/ecommerce.db <<EOF
CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, region TEXT);
CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, amount REAL, order_date TEXT);

INSERT INTO customers (id, name, region) VALUES 
(1, 'Alice', 'North America'),
(2, 'Bob', 'North America'),
(3, 'Charlie', 'North America'),
(4, 'Diana', 'Europe'),
(5, 'Eve', 'North America');

INSERT INTO orders (id, customer_id, amount, order_date) VALUES 
(1, 1, 500.0, '2023-01-01'),
(2, 2, 150.0, '2023-01-02'),
(3, 3, 200.0, '2023-01-03'),
(4, 3, 100.0, '2023-01-04'),
(5, 4, 1000.0, '2023-01-05'),
(6, 5, 50.0, '2023-01-06'),
(7, 1, 100.0, '2023-01-07');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
