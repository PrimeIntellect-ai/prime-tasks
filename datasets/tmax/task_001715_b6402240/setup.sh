#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE customers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT NOT NULL
);

CREATE TABLE orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL,
    order_date TEXT NOT NULL
);

CREATE TABLE order_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price REAL NOT NULL
);

INSERT INTO customers (name, email) VALUES ('Alice Smith', 'alice@example.com'), ('Bob Jones', 'bob@example.com'), ('Charlie Brown', 'charlie@example.com');
INSERT INTO orders (customer_id, order_date) VALUES (1, '2023-10-15'), (2, '2023-10-15'), (1, '2023-10-16');
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES (1, 101, 2, 15.50), (1, 102, 1, 9.00), (2, 103, 5, 4.20), (3, 101, 1, 15.50);
EOF

    sqlite3 /home/user/source.db < /tmp/setup_db.sql
    rm /tmp/setup_db.sql

    chmod -R 777 /home/user
