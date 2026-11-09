#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/company.db <<EOF
CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER, FOREIGN KEY(dept_id) REFERENCES departments(id));
CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE employee_projects (emp_id INTEGER, proj_id INTEGER, FOREIGN KEY(emp_id) REFERENCES employees(id), FOREIGN KEY(proj_id) REFERENCES projects(id));

INSERT INTO departments VALUES (1, 'Engineering'), (2, 'Marketing');
INSERT INTO employees VALUES (101, 'Alice', 1), (102, 'Bob', 1), (103, 'Charlie', 2);
INSERT INTO projects VALUES (1001, 'Migration'), (1002, 'Analytics'), (1003, 'Campaign');

INSERT INTO employee_projects VALUES (101, 1001), (101, 1002), (102, 1001), (103, 1003);
EOF

    chmod -R 777 /home/user
