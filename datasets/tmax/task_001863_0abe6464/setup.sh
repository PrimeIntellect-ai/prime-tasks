#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, emp_id INTEGER, resource_id INTEGER, bytes_transferred INTEGER);

INSERT INTO employees VALUES (1, 'Alice (CEO)', NULL);
INSERT INTO employees VALUES (2, 'Bob (VP)', 1);
INSERT INTO employees VALUES (3, 'Charlie (VP)', 1);
INSERT INTO employees VALUES (4, 'David (Dir)', 2);
INSERT INTO employees VALUES (5, 'Eve (Worker)', 4);
INSERT INTO employees VALUES (6, 'Frank (Worker)', 4);
INSERT INTO employees VALUES (7, 'Grace (Worker)', 3);

-- Resource 100
INSERT INTO access_logs VALUES (1, 5, 100, 300);
INSERT INTO access_logs VALUES (2, 5, 100, 300);
INSERT INTO access_logs VALUES (3, 6, 100, 800);
INSERT INTO access_logs VALUES (4, 4, 100, 400);
INSERT INTO access_logs VALUES (5, 7, 100, 900);

-- Resource 200
INSERT INTO access_logs VALUES (6, 2, 200, 600);
INSERT INTO access_logs VALUES (7, 4, 200, 600);
INSERT INTO access_logs VALUES (8, 6, 200, 400);
INSERT INTO access_logs VALUES (9, 1, 200, 2000);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
