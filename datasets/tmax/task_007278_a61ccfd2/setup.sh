#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/company.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
CREATE TABLE sales (id INTEGER PRIMARY KEY, employee_id INTEGER, sale_date TEXT, amount REAL);

INSERT INTO employees VALUES (1, 'Alice', NULL);
INSERT INTO employees VALUES (2, 'Bob', 1);
INSERT INTO employees VALUES (3, 'Charlie', 1);
INSERT INTO employees VALUES (4, 'Dave', 2);
INSERT INTO employees VALUES (5, 'Eve', 3);
INSERT INTO employees VALUES (6, 'Frank', NULL);

INSERT INTO sales VALUES (1, 1, '2023-10-01', 100);
INSERT INTO sales VALUES (2, 2, '2023-10-01', 150);
INSERT INTO sales VALUES (3, 6, '2023-10-01', 500);
INSERT INTO sales VALUES (4, 3, '2023-10-02', 200);
INSERT INTO sales VALUES (5, 4, '2023-10-03', 300);
INSERT INTO sales VALUES (6, 5, '2023-10-04', 100);
INSERT INTO sales VALUES (7, 1, '2023-10-05', 50);
INSERT INTO sales VALUES (8, 2, '2023-10-06', 400);
INSERT INTO sales VALUES (9, 3, '2023-10-07', 100);
EOF

    chmod -R 777 /home/user
