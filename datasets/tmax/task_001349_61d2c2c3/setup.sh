#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/audit.db << 'EOF'
CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, department TEXT);
CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, emp_id INTEGER, amount REAL, tx_date TEXT);

INSERT INTO employees VALUES (1, 'Alice', NULL, 'Exec');
INSERT INTO employees VALUES (2, 'Bob', 1, 'Sales');
INSERT INTO employees VALUES (3, 'Charlie', 1, 'Engineering');
INSERT INTO employees VALUES (4, 'Dave', 2, 'Sales');
INSERT INTO employees VALUES (5, 'Eve', 2, 'Sales');
INSERT INTO employees VALUES (6, 'Frank', 3, 'Engineering');
INSERT INTO employees VALUES (7, 'Grace', 3, 'Engineering');

INSERT INTO transactions VALUES (101, 4, 100.0, '2023-01-01');
INSERT INTO transactions VALUES (102, 4, 150.0, '2023-01-02');
INSERT INTO transactions VALUES (103, 5, 120.0, '2023-01-03');
INSERT INTO transactions VALUES (104, 5, 1500.0, '2023-01-04');
INSERT INTO transactions VALUES (105, 6, 200.0, '2023-01-01');
INSERT INTO transactions VALUES (106, 6, 250.0, '2023-01-02');
INSERT INTO transactions VALUES (107, 7, 300.0, '2023-01-03');
INSERT INTO transactions VALUES (108, 7, 3000.0, '2023-01-05');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
