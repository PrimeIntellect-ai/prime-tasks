#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo rustc libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/compliance.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
CREATE TABLE assets (id INTEGER PRIMARY KEY, employee_id INTEGER, asset_tag TEXT, value INTEGER);

INSERT INTO employees (id, name, manager_id) VALUES 
(1, 'Alice', NULL),
(2, 'Bob', 1),
(3, 'Charlie', 1),
(4, 'Diana', 2),
(5, 'Eve', 3),
(6, 'Frank', 3);

INSERT INTO assets (id, employee_id, asset_tag, value) VALUES 
(101, 1, 'LAPTOP-01', 2000),
(102, 2, 'SERVER-01', 5000),
(103, 2, 'DESKTOP-01', 1000),
(104, 3, 'LAPTOP-02', 1500),
(105, 4, 'PHONE-01', 500),
(106, 6, 'LAPTOP-03', 2200),
(107, 6, 'MONITOR-01', 300);

CREATE INDEX idx_employee_assets ON assets(employee_id);
EOF

    chmod -R 777 /home/user
