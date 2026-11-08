#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user

sqlite3 /home/user/company.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, salary INTEGER, department TEXT);
INSERT INTO employees VALUES (1, 'CEO', NULL, 200000, 'Exec');
INSERT INTO employees VALUES (2, 'VP Eng', 1, 150000, 'Eng');
INSERT INTO employees VALUES (3, 'VP Sales', 1, 140000, 'Sales');
INSERT INTO employees VALUES (4, 'Director Eng', 2, 120000, 'Eng');
INSERT INTO employees VALUES (5, 'Eng Manager', 4, 100000, 'Eng');
INSERT INTO employees VALUES (6, 'Senior Eng 1', 5, 95000, 'Eng');
INSERT INTO employees VALUES (7, 'Senior Eng 2', 5, 95000, 'Eng');
INSERT INTO employees VALUES (8, 'Junior Eng 1', 5, 70000, 'Eng');
INSERT INTO employees VALUES (9, 'Junior Eng 2', 5, 65000, 'Eng');
INSERT INTO employees VALUES (10, 'Sales Manager', 3, 90000, 'Sales');
EOF

chmod -R 777 /home/user
