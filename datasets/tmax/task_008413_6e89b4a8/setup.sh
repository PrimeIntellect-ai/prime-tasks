#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential jq
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    sqlite3 /home/user/data/company.db <<EOF
CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department_id INTEGER, salary REAL);
CREATE TABLE reporting_lines (manager_id INTEGER, subordinate_id INTEGER);

INSERT INTO departments VALUES (1, 'Executive');
INSERT INTO departments VALUES (2, 'Backend');
INSERT INTO departments VALUES (3, 'Frontend');
INSERT INTO departments VALUES (4, 'DevOps');
INSERT INTO departments VALUES (5, 'Sales');

INSERT INTO employees VALUES (1, 'Alice', 1, 300000);
INSERT INTO employees VALUES (2, 'Bob', 2, 120000);
INSERT INTO employees VALUES (3, 'Charlie', 2, 110000);
INSERT INTO employees VALUES (4, 'David', 2, 90000);
INSERT INTO employees VALUES (5, 'Eve', 3, 115000);
INSERT INTO employees VALUES (6, 'Frank', 3, 95000);
INSERT INTO employees VALUES (7, 'Grace', 4, 130000);
INSERT INTO employees VALUES (8, 'Heidi', 5, 100000);

INSERT INTO reporting_lines VALUES (1, 2);
INSERT INTO reporting_lines VALUES (1, 5);
INSERT INTO reporting_lines VALUES (1, 7);
INSERT INTO reporting_lines VALUES (2, 3);
INSERT INTO reporting_lines VALUES (2, 4);
INSERT INTO reporting_lines VALUES (5, 6);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
