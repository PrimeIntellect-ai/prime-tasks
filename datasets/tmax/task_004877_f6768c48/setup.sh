#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, department TEXT);
CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, emp_id INTEGER, resource TEXT, status TEXT, timestamp DATETIME);

INSERT INTO employees VALUES (1, 'Alice', NULL, 'Executive');
INSERT INTO employees VALUES (2, 'Bob', 1, 'Engineering');
INSERT INTO employees VALUES (3, 'Charlie', 2, 'Engineering');
INSERT INTO employees VALUES (4, 'Diana', 1, 'Sales');
INSERT INTO employees VALUES (5, 'Eve', 4, 'Sales');
INSERT INTO employees VALUES (6, 'Frank', 2, 'Engineering');
INSERT INTO employees VALUES (7, 'Grace', 3, 'Engineering');

INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (3, 'R1', 'DENIED', '2023-01-01');
INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (3, 'R2', 'DENIED', '2023-01-02');
INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (3, 'R3', 'DENIED', '2023-01-03');
INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (3, 'R4', 'DENIED', '2023-01-04');
INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (3, 'R5', 'DENIED', '2023-01-05');

INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (6, 'R1', 'DENIED', '2023-01-01');
INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (6, 'R1', 'DENIED', '2023-01-02');

INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (5, 'R2', 'DENIED', '2023-01-01');
INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (5, 'R2', 'DENIED', '2023-01-02');
INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (5, 'R2', 'DENIED', '2023-01-03');

INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (2, 'R1', 'DENIED', '2023-01-01');
INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (2, 'R1', 'SUCCESS', '2023-01-02');
INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (2, 'R1', 'SUCCESS', '2023-01-03');

INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (7, 'R1', 'DENIED', '2023-01-01');
INSERT INTO access_logs (emp_id, resource, status, timestamp) VALUES (7, 'R1', 'DENIED', '2023-01-02');
EOF

    sqlite3 /home/user/corporate.db < /tmp/setup_db.sql
    chown user:user /home/user/corporate.db

    chmod -R 777 /home/user
