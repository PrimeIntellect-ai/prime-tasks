#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    sqlite3 warehouse.db <<EOF
CREATE TABLE sys_dim_a (
    a_id INTEGER PRIMARY KEY,
    category_name TEXT,
    status TEXT
);

CREATE TABLE sys_dim_b (
    b_id INTEGER PRIMARY KEY,
    region_code TEXT
);

CREATE TABLE sys_trx_01 (
    t_id INTEGER PRIMARY KEY,
    dim_a_id INTEGER,
    dim_b_id INTEGER,
    amount REAL,
    ts DATETIME,
    FOREIGN KEY(dim_a_id) REFERENCES sys_dim_a(a_id),
    FOREIGN KEY(dim_b_id) REFERENCES sys_dim_b(b_id)
);

INSERT INTO sys_dim_a (a_id, category_name, status) VALUES 
(1, 'Electronics', 'active'),
(2, 'Books', 'active'),
(3, 'Clothing', 'inactive');

INSERT INTO sys_dim_b (b_id, region_code) VALUES 
(10, 'East'),
(20, 'West');

-- East, Active, after 2023
INSERT INTO sys_trx_01 (dim_a_id, dim_b_id, amount, ts) VALUES (1, 10, 150.50, '2023-05-01 10:00:00');
INSERT INTO sys_trx_01 (dim_a_id, dim_b_id, amount, ts) VALUES (1, 10, 49.50, '2023-06-01 10:00:00');
INSERT INTO sys_trx_01 (dim_a_id, dim_b_id, amount, ts) VALUES (2, 10, 20.00, '2023-07-01 10:00:00');

-- East, Active, BEFORE 2023 (should be excluded)
INSERT INTO sys_trx_01 (dim_a_id, dim_b_id, amount, ts) VALUES (1, 10, 500.00, '2022-05-01 10:00:00');

-- West, Active (should be excluded)
INSERT INTO sys_trx_01 (dim_a_id, dim_b_id, amount, ts) VALUES (1, 20, 300.00, '2023-08-01 10:00:00');

-- East, Inactive (should be excluded)
INSERT INTO sys_trx_01 (dim_a_id, dim_b_id, amount, ts) VALUES (3, 10, 99.99, '2023-09-01 10:00:00');
EOF

    chmod -R 777 /home/user
