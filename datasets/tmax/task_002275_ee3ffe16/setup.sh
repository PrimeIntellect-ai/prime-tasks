#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/ecommerce.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE products (id INTEGER PRIMARY KEY, title TEXT, category TEXT);
CREATE TABLE purchases (id INTEGER PRIMARY KEY, user_id INTEGER, product_id INTEGER, purchase_date TEXT);
CREATE TABLE reviews (id INTEGER PRIMARY KEY, user_id INTEGER, product_id INTEGER, rating INTEGER, review_text TEXT);

INSERT INTO users (id, name) VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie'), (4, 'Diana');

INSERT INTO products (id, title, category) VALUES 
(101, 'Cheap Headphones', 'Electronics'),
(102, 'Nice Keyboard', 'Electronics'),
(103, 'Desk Lamp', 'Home'),
(104, 'Broken Mug', 'Home'),
(105, 'Data Science Book', 'Books'),
(106, 'Ergonomic Chair', 'Home');

-- Alice bought Cheap Headphones (101), Nice Keyboard (102), and Desk Lamp (103)
INSERT INTO purchases (user_id, product_id, purchase_date) VALUES 
(1, 101, '2023-01-01'),
(1, 102, '2023-01-02'),
(1, 103, '2023-01-03');
-- Alice reviews Cheap Headphones as 1-star
INSERT INTO reviews (user_id, product_id, rating, review_text) VALUES 
(1, 101, 1, 'Terrible sound');

-- Bob bought Broken Mug (104), Data Science Book (105), Nice Keyboard (102)
INSERT INTO purchases (user_id, product_id, purchase_date) VALUES 
(2, 104, '2023-02-01'),
(2, 105, '2023-02-02'),
(2, 102, '2023-02-03');
-- Bob reviews Broken Mug as 1-star
INSERT INTO reviews (user_id, product_id, rating, review_text) VALUES 
(2, 104, 1, 'Arrived in pieces');

-- Charlie bought Desk Lamp (103) and Ergonomic Chair (106), no 1-star reviews
INSERT INTO purchases (user_id, product_id, purchase_date) VALUES 
(3, 103, '2023-03-01'),
(3, 106, '2023-03-02');
INSERT INTO reviews (user_id, product_id, rating, review_text) VALUES 
(3, 103, 5, 'Great lamp');

EOF

    chmod -R 777 /home/user
