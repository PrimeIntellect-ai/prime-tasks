#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/ecommerce.db <<EOF
CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE products (id INTEGER PRIMARY KEY, category_id INTEGER, name TEXT, price REAL);
CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, order_date TEXT);
CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER);

INSERT INTO categories VALUES (1, 'Electronics'), (2, 'Books'), (3, 'Clothing');
INSERT INTO products VALUES (1, 1, 'Laptop', 999.99), (2, 1, 'Mouse', 25.50), (3, 1, 'Keyboard', 45.00), (4, 1, 'Monitor', 200.00);
INSERT INTO products VALUES (5, 2, 'Sci-Fi Novel', 15.00), (6, 2, 'History Book', 22.00), (7, 2, 'Cooking Guide', 30.00);
INSERT INTO products VALUES (8, 3, 'T-Shirt', 10.00), (9, 3, 'Jeans', 40.00), (10, 3, 'Jacket', 120.00);

-- 2023 Orders
INSERT INTO orders VALUES (1, 101, '2023-05-10'), (2, 102, '2023-08-21'), (3, 103, '2023-11-05');
-- 2022 Orders (Should be ignored)
INSERT INTO orders VALUES (4, 104, '2022-12-01');

INSERT INTO order_items VALUES (1, 1, 1, 2); -- Laptop: 1999.98
INSERT INTO order_items VALUES (2, 1, 2, 5); -- Mouse: 127.50
INSERT INTO order_items VALUES (3, 2, 4, 3); -- Monitor: 600.00
INSERT INTO order_items VALUES (4, 3, 5, 10); -- Sci-Fi: 150.00
INSERT INTO order_items VALUES (5, 3, 6, 2); -- History: 44.00
INSERT INTO order_items VALUES (6, 1, 10, 1); -- Jacket: 120.00
INSERT INTO order_items VALUES (7, 4, 1, 10); -- Ignored 2022 order
EOF

    chmod -R 777 /home/user
