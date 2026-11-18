#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/corp.db <<EOF
CREATE TABLE departments (dept_id INTEGER PRIMARY KEY, dept_name TEXT);
CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, dept_id INTEGER);

INSERT INTO departments VALUES (10, 'Executive');
INSERT INTO departments VALUES (20, 'Engineering');
INSERT INTO departments VALUES (30, 'Sales');
INSERT INTO departments VALUES (40, 'HR');

INSERT INTO employees VALUES (1, 'Alice', NULL, 10);
INSERT INTO employees VALUES (2, 'Bob', 1, 20);
INSERT INTO employees VALUES (3, 'Charlie', 1, 30);
INSERT INTO employees VALUES (4, 'David', 2, 20);
INSERT INTO employees VALUES (5, 'Eve', 2, 20);
INSERT INTO employees VALUES (6, 'Frank', 3, 30);
INSERT INTO employees VALUES (7, 'Grace', 6, 30);
INSERT INTO employees VALUES (8, 'Heidi', 1, 40);
EOF

    chmod -R 777 /home/user
