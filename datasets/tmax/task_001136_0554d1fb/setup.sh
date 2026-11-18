#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/company.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
CREATE TABLE manager (emp_id INTEGER, manager_id INTEGER);

INSERT INTO employees VALUES (1, 'Alice CEO', 'Executive');
INSERT INTO employees VALUES (2, 'Bob VP', 'Sales');
INSERT INTO employees VALUES (3, 'Charlie VP', 'Engineering');
INSERT INTO employees VALUES (4, 'Dave Dir', 'Sales');
INSERT INTO employees VALUES (5, 'Eve Dir', 'Engineering');
INSERT INTO employees VALUES (6, 'Frank Mgr', 'Sales');
INSERT INTO employees VALUES (7, 'Grace Mgr', 'Engineering');
INSERT INTO employees VALUES (8, 'Heidi IC', 'Sales');
INSERT INTO employees VALUES (9, 'Ivan IC', 'Engineering');
INSERT INTO employees VALUES (10, 'Judy IC', 'Engineering');

INSERT INTO manager VALUES (2, 1);
INSERT INTO manager VALUES (3, 1);
INSERT INTO manager VALUES (4, 2);
INSERT INTO manager VALUES (5, 3);
INSERT INTO manager VALUES (6, 4);
INSERT INTO manager VALUES (7, 5);
INSERT INTO manager VALUES (8, 6);
INSERT INTO manager VALUES (9, 7);
INSERT INTO manager VALUES (10, 7);
EOF

    chmod -R 777 /home/user
