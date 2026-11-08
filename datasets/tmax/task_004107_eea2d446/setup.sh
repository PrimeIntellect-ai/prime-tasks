#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    # Create database
    sqlite3 company.db <<EOF
CREATE TABLE departments (
    dept_id INTEGER PRIMARY KEY,
    dept_name TEXT
);

CREATE TABLE employees (
    emp_id INTEGER PRIMARY KEY,
    name TEXT,
    dept_id INTEGER,
    salary INTEGER
);

CREATE TABLE reports_to (
    mgr_id INTEGER,
    emp_id INTEGER,
    PRIMARY KEY (mgr_id, emp_id)
);

INSERT INTO departments VALUES (1, 'Engineering');
INSERT INTO departments VALUES (2, 'Sales');
INSERT INTO departments VALUES (3, 'HR');

-- Engineering
INSERT INTO employees VALUES (101, 'Alice', 1, 120000);
INSERT INTO employees VALUES (102, 'Bob', 1, 110000);
INSERT INTO employees VALUES (103, 'Charlie', 1, 100000);
INSERT INTO employees VALUES (104, 'Dave', 1, 95000);
INSERT INTO employees VALUES (105, 'Eve', 1, 120000);

-- Sales
INSERT INTO employees VALUES (201, 'Frank', 2, 80000);
INSERT INTO employees VALUES (202, 'Grace', 2, 85000);
INSERT INTO employees VALUES (203, 'Heidi', 2, 90000);

-- HR
INSERT INTO employees VALUES (301, 'Ivan', 3, 75000);
INSERT INTO employees VALUES (302, 'Judy', 3, 70000);

-- Reports To
-- Alice has 2 reports (103, 104)
INSERT INTO reports_to VALUES (101, 103);
INSERT INTO reports_to VALUES (101, 104);

-- Eve has 2 reports (102, 101)
INSERT INTO reports_to VALUES (105, 102);
INSERT INTO reports_to VALUES (105, 101);

-- Heidi has 1 report
INSERT INTO reports_to VALUES (203, 201);
-- Grace has 1 report
INSERT INTO reports_to VALUES (202, 203);
EOF

    chmod -R 777 /home/user
