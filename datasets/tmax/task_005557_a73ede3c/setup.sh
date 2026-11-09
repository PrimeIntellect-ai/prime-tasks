#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE reporting (assignment_id INTEGER PRIMARY KEY, emp_id INTEGER, manager_id INTEGER, assigned_date TEXT);

INSERT INTO employees VALUES (1, 'Alice');
INSERT INTO employees VALUES (2, 'Bob');
INSERT INTO employees VALUES (3, 'Charlie');
INSERT INTO employees VALUES (4, 'David');
INSERT INTO employees VALUES (5, 'Eve');

-- Bob reports to Alice
INSERT INTO reporting VALUES (1, 2, 1, '2020-01-01');
-- Charlie reports to Bob
INSERT INTO reporting VALUES (2, 3, 2, '2020-02-01');
-- David reports to Charlie
INSERT INTO reporting VALUES (3, 4, 3, '2021-01-01');
-- David used to report to Bob (STALE ROW)
INSERT INTO reporting VALUES (4, 4, 2, '2019-01-01');
-- Eve reports to David
INSERT INTO reporting VALUES (5, 5, 4, '2022-01-01');
-- Eve used to report to Alice (STALE ROW)
INSERT INTO reporting VALUES (6, 5, 1, '2018-01-01');
EOF

    sqlite3 /home/user/company.db < /home/user/setup_db.sql
    rm /home/user/setup_db.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
