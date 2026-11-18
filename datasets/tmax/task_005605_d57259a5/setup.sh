#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/ecommerce.db <<EOF
CREATE TABLE client (id INTEGER PRIMARY KEY, name TEXT, join_date TEXT);
CREATE TABLE cart (id INTEGER PRIMARY KEY, client_id INTEGER, checkout_date TEXT);
CREATE TABLE product (id INTEGER PRIMARY KEY, name TEXT, price REAL);
CREATE TABLE cart_item (id INTEGER PRIMARY KEY, cart_id INTEGER, product_id INTEGER, quantity INTEGER);

INSERT INTO client VALUES (1, 'Alice', '2022-01-01');
INSERT INTO client VALUES (2, 'Bob', '2022-02-01');
INSERT INTO client VALUES (3, 'Charlie', '2022-03-01');
INSERT INTO client VALUES (4, 'David', '2022-04-01');
INSERT INTO client VALUES (5, 'Eve', '2022-05-01');
INSERT INTO client VALUES (6, 'Frank', '2022-06-01');

INSERT INTO product VALUES (1, 'Widget A', 10.50);
INSERT INTO product VALUES (2, 'Widget B', 20.00);
INSERT INTO product VALUES (3, 'Widget C', 5.25);

INSERT INTO cart VALUES (1, 1, '2023-05-15');
INSERT INTO cart VALUES (2, 2, '2023-06-20');
INSERT INTO cart VALUES (3, 3, '2023-07-10');
INSERT INTO cart VALUES (4, 4, '2023-08-05');
INSERT INTO cart VALUES (5, 5, '2023-09-12');
INSERT INTO cart VALUES (6, 6, '2024-01-10');
INSERT INTO cart VALUES (7, 1, '2023-11-01');

INSERT INTO cart_item VALUES (1, 1, 1, 5);
INSERT INTO cart_item VALUES (2, 1, 2, 2);
INSERT INTO cart_item VALUES (3, 2, 3, 10);
INSERT INTO cart_item VALUES (4, 3, 1, 10);
INSERT INTO cart_item VALUES (5, 4, 2, 3);
INSERT INTO cart_item VALUES (6, 5, 3, 20);
INSERT INTO cart_item VALUES (7, 6, 1, 100);
INSERT INTO cart_item VALUES (8, 7, 2, 1);
EOF

    chmod -R 777 /home/user
