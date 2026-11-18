#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    sqlite3 audit.db <<EOF
CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, department TEXT);
CREATE TABLE resources (resource_id INTEGER PRIMARY KEY, name TEXT, sensitivity TEXT);
CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, emp_id INTEGER, resource_id INTEGER, timestamp DATETIME);

INSERT INTO employees VALUES (1, 'Alice', 'Engineering');
INSERT INTO employees VALUES (2, 'Bob', 'Engineering');
INSERT INTO employees VALUES (3, 'Charlie', 'Engineering');
INSERT INTO employees VALUES (4, 'Diana', 'HR');
INSERT INTO employees VALUES (5, 'Eve', 'HR');

INSERT INTO resources VALUES (101, 'Source Code', 'HIGH');
INSERT INTO resources VALUES (102, 'Customer DB', 'HIGH');
INSERT INTO resources VALUES (103, 'Cafeteria Menu', 'LOW');
INSERT INTO resources VALUES (104, 'Payroll System', 'HIGH');

INSERT INTO access_logs (emp_id, resource_id) VALUES (1, 101), (1, 102), (1, 101);
INSERT INTO access_logs (emp_id, resource_id) VALUES (2, 101);
INSERT INTO access_logs (emp_id, resource_id) VALUES (3, 102), (3, 102);
INSERT INTO access_logs (emp_id, resource_id) VALUES (4, 104);
INSERT INTO access_logs (emp_id, resource_id) VALUES (5, 104), (5, 102);
INSERT INTO access_logs (emp_id, resource_id) VALUES (1, 103), (2, 103), (3, 103), (4, 103), (5, 103);
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
