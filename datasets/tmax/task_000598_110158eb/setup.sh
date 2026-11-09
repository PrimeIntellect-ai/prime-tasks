#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/company.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT, salary INTEGER, manager_id INTEGER);
INSERT INTO employees VALUES (1, 'Alice', 'Executive', 300000, NULL);
INSERT INTO employees VALUES (2, 'Bob', 'Engineering', 200000, 1);
INSERT INTO employees VALUES (3, 'Charlie', 'Sales', 180000, 1);
INSERT INTO employees VALUES (4, 'Dave', 'Engineering', 150000, 2);
INSERT INTO employees VALUES (5, 'Eve', 'Engineering', 160000, 4);
INSERT INTO employees VALUES (6, 'Frank', 'Engineering', 100000, 4);
INSERT INTO employees VALUES (7, 'Grace', 'Engineering', 90000, 4);
INSERT INTO employees VALUES (8, 'Heidi', 'Sales', 190000, 3);
INSERT INTO employees VALUES (9, 'Ivan', 'Sales', 80000, 3);
EOF

    chmod -R 777 /home/user
