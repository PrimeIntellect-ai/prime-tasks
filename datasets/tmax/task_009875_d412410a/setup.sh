#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/company_data.db <<EOF
CREATE TABLE departments (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE employees (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    manager_id INTEGER,
    dept_id INTEGER,
    FOREIGN KEY(manager_id) REFERENCES employees(id),
    FOREIGN KEY(dept_id) REFERENCES departments(id)
);

CREATE TABLE assets (
    id INTEGER PRIMARY KEY,
    asset_name TEXT NOT NULL,
    cost REAL NOT NULL,
    owner_id INTEGER,
    FOREIGN KEY(owner_id) REFERENCES employees(id)
);

INSERT INTO departments VALUES (1, 'Executive'), (2, 'Engineering'), (3, 'Sales');

INSERT INTO employees VALUES 
(1, 'Alice Smith', NULL, 1),
(2, 'Bob Jones', 1, 2),
(3, 'Charlie Brown', 1, 3),
(4, 'Diana Prince', 2, 2),
(5, 'Evan Wright', 4, 2),
(6, 'Fiona Gallagher', 3, 3);

INSERT INTO assets VALUES 
(101, 'MacBook Pro', 2000, 1),
(102, 'ThinkPad', 1500, 2),
(103, 'iPhone', 500, 2),
(104, 'ThinkPad', 1500, 3),
(105, 'Desktop Workstation', 2500, 4),
(106, 'Chromebook', 1000, 5),
(107, 'External Monitor', 300, 5);
EOF

    chmod -R 777 /home/user
