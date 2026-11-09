#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/company.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
CREATE TABLE salaries (employee_id INTEGER, salary INTEGER);

INSERT INTO employees (id, name, manager_id) VALUES 
(1, 'Evelyn', NULL),
(2, 'Bob', 1),
(3, 'Charlie', 1),
(4, 'Dave', 2),
(5, 'Eve', 2),
(6, 'Alice', 3),
(7, 'Frank', NULL),
(8, 'Grace', 7);

INSERT INTO salaries (employee_id, salary) VALUES 
(1, 100000),
(2, 80000),
(3, 60000),
(4, 50000),
(5, 55000),
(6, 45000),
(7, 90000),
(8, 70000);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
