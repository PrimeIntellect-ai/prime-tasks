#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
PRAGMA foreign_keys = OFF;

CREATE TABLE customers (
    id INTEGER PRIMARY KEY,
    name TEXT
);

CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    customer_id INTEGER,
    amount REAL,
    FOREIGN KEY(customer_id) REFERENCES customers(id)
);

CREATE TABLE payments (
    id INTEGER PRIMARY KEY,
    order_id INTEGER,
    amount REAL,
    FOREIGN KEY(order_id) REFERENCES orders(id)
);

INSERT INTO customers (id, name) VALUES (1, 'Alice'), (2, 'Bob');

-- Valid orders
INSERT INTO orders (id, customer_id, amount) VALUES (101, 1, 50.00);
INSERT INTO orders (id, customer_id, amount) VALUES (102, 2, 75.50);

-- Orphaned orders (customer_id 99 and 98 do not exist)
INSERT INTO orders (id, customer_id, amount) VALUES (103, 99, 120.25);
INSERT INTO orders (id, customer_id, amount) VALUES (104, 98, 80.50);

-- Valid payments
INSERT INTO payments (id, order_id, amount) VALUES (1001, 101, 50.00);
INSERT INTO payments (id, order_id, amount) VALUES (1002, 102, 75.50);

-- Orphaned payments (order_id 999 does not exist)
INSERT INTO payments (id, order_id, amount) VALUES (1003, 999, 300.75);

PRAGMA foreign_keys = ON;
EOF

    sqlite3 /home/user/db_backup.sqlite < /tmp/setup_db.sql

    chmod -R 777 /home/user
