#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/company.db <<EOF
CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT NOT NULL, department_id INTEGER NOT NULL, manager_id INTEGER, salary REAL NOT NULL, FOREIGN KEY(department_id) REFERENCES departments(id), FOREIGN KEY(manager_id) REFERENCES employees(id));

INSERT INTO departments VALUES (1, 'Executive');
INSERT INTO departments VALUES (2, 'Engineering');
INSERT INTO departments VALUES (3, 'Sales');

INSERT INTO employees VALUES (1, 'Alice', 1, NULL, 200000);
INSERT INTO employees VALUES (2, 'Bob', 1, 1, 150000);
INSERT INTO employees VALUES (3, 'Charlie', 2, 1, 140000);
INSERT INTO employees VALUES (4, 'Dave', 1, 2, 120000);
INSERT INTO employees VALUES (5, 'Eve', 2, 3, 110000);
INSERT INTO employees VALUES (10, 'Judy', 3, 2, 95000);
INSERT INTO employees VALUES (7, 'Grace', 1, 4, 90000);
INSERT INTO employees VALUES (9, 'Ivan', 2, 5, 87000);
INSERT INTO employees VALUES (8, 'Heidi', 2, 5, 85000);
INSERT INTO employees VALUES (6, 'Frank', 3, 4, 80000);
EOF

    chmod -R 777 /home/user
