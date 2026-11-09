#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/company.db <<'EOF'
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
CREATE TABLE sales (id INTEGER PRIMARY KEY, emp_id INTEGER, amount INTEGER, sale_date TEXT);

INSERT INTO employees VALUES (1, 'Alice', NULL);
INSERT INTO employees VALUES (2, 'Bob', 1);
INSERT INTO employees VALUES (3, 'Charlie', 1);
INSERT INTO employees VALUES (4, 'Dave', 2);
INSERT INTO employees VALUES (5, 'Eve', 2);
INSERT INTO employees VALUES (6, 'Frank', 3);
INSERT INTO employees VALUES (7, 'Grace', 3);

INSERT INTO sales VALUES (1, 4, 100, '2023-01-01');
INSERT INTO sales VALUES (2, 4, 150, '2023-01-02');
INSERT INTO sales VALUES (3, 5, 200, '2023-01-01');
INSERT INTO sales VALUES (4, 5, 300, '2023-01-03');
INSERT INTO sales VALUES (5, 6, 400, '2023-01-02');
INSERT INTO sales VALUES (6, 7, 500, '2023-01-04');

CREATE INDEX idx_sales_date ON sales(sale_date);
EOF

    chmod -R 777 /home/user
