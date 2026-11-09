#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/db
    cd /home/user/db

    sqlite3 org_chart.db <<EOF
CREATE TABLE employees(emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
INSERT INTO employees (emp_id, name, manager_id) VALUES 
(1, 'CEO', NULL),
(2, 'VP1', 1),
(3, 'VP2', 1),
(4, 'Director1', 2),
(5, 'Director2', 2),
(6, 'Director3', 3),
(7, 'IC1', 4),
(8, 'IC2', 4),
(9, 'IC3', 4),
(10, 'IC4', 5),
(11, 'IC5', 5),
(12, 'IC6', 6);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
