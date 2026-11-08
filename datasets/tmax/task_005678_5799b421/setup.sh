#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/compliance.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
CREATE TABLE access_grants (employee_id INTEGER, system_name TEXT);

INSERT INTO employees (id, name, manager_id) VALUES 
(1, 'Alice', NULL),
(2, 'Bob', 1),
(3, 'Charlie', 2),
(4, 'Dave', 3),
(5, 'Eve', 4),
(6, 'Frank', 4),
(7, 'Grace', 5),
(8, 'Heidi', 2),
(9, 'Ivan', 8),
(10, 'Judy', 9),
(11, 'Mallory', 10),
(12, 'Trent', 11);

INSERT INTO access_grants (employee_id, system_name) VALUES 
(1, 'Project_Zeus'),
(4, 'Project_Zeus'),
(8, 'Project_Zeus'),
(3, 'Project_Apollo'),
(9, 'Project_Apollo');
EOF

    chmod -R 777 /home/user
