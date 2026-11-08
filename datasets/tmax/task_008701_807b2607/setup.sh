#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/company.db <<EOF
CREATE TABLE departments (
    dept_id INTEGER PRIMARY KEY,
    department_name TEXT NOT NULL
);

CREATE TABLE employees (
    emp_id INTEGER PRIMARY KEY,
    emp_name TEXT NOT NULL,
    dept_id INTEGER,
    salary INTEGER,
    FOREIGN KEY(dept_id) REFERENCES departments(dept_id)
);

INSERT INTO departments (dept_id, department_name) VALUES (1, 'Engineering');
INSERT INTO departments (dept_id, department_name) VALUES (2, 'Sales');
INSERT INTO departments (dept_id, department_name) VALUES (3, 'Marketing');

INSERT INTO employees (emp_id, emp_name, dept_id, salary) VALUES (1, 'Alice', 1, 120000);
INSERT INTO employees (emp_id, emp_name, dept_id, salary) VALUES (2, 'Bob', 1, 110000);
INSERT INTO employees (emp_id, emp_name, dept_id, salary) VALUES (3, 'Charlie', 2, 85000);
INSERT INTO employees (emp_id, emp_name, dept_id, salary) VALUES (4, 'Diana', 2, 90000);
INSERT INTO employees (emp_id, emp_name, dept_id, salary) VALUES (5, 'Eve', 3, 75000);

CREATE INDEX idx_emp_dept ON employees(dept_id);
EOF

    chmod -R 777 /home/user
