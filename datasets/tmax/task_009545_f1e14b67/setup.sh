#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE employees(id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, department TEXT);
CREATE TABLE access(employee_id INTEGER, system_name TEXT, risk_level INTEGER);

INSERT INTO employees VALUES (1, 'Alice Smith', NULL, 'Engineering');
INSERT INTO employees VALUES (2, 'Bob Jones', 1, 'Engineering');
INSERT INTO employees VALUES (3, 'Charlie Brown', 2, 'Engineering');
INSERT INTO employees VALUES (4, 'Diana Prince', NULL, 'Finance');
INSERT INTO employees VALUES (5, 'Evan Wright', 4, 'Finance');

INSERT INTO access VALUES (1, 'GitLab', 3);
INSERT INTO access VALUES (2, 'AWS Prod', 9);
INSERT INTO access VALUES (3, 'AWS Dev', 5);
INSERT INTO access VALUES (3, 'Jenkins', 9);
INSERT INTO access VALUES (4, 'Stripe', 8);
INSERT INTO access VALUES (5, 'Payroll System', 10);
EOF

    sqlite3 /home/user/audit.db < /home/user/setup_db.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
