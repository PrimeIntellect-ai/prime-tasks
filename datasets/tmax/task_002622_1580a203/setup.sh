#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev cargo rustc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/compliance.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
CREATE TABLE resources (id INTEGER PRIMARY KEY, name TEXT, sensitivity TEXT);
CREATE TABLE access_grants (emp_id INTEGER, resource_id INTEGER, grant_date TEXT);

INSERT INTO employees VALUES (1, 'Alice', 'Finance');
INSERT INTO employees VALUES (2, 'Bob', 'Finance');
INSERT INTO employees VALUES (3, 'Charlie', 'Engineering');
INSERT INTO employees VALUES (4, 'Diana', 'Finance');

INSERT INTO resources VALUES (101, 'Financial_Q1', 'HIGH');
INSERT INTO resources VALUES (102, 'Financial_Q2', 'HIGH');
INSERT INTO resources VALUES (103, 'Public_Docs', 'LOW');
INSERT INTO resources VALUES (104, 'M_A_Strategy', 'HIGH');
INSERT INTO resources VALUES (105, 'Eng_Code', 'HIGH');

-- Alice gets 2 high sensitivity resources
INSERT INTO access_grants VALUES (1, 101, '2023-01-01');
INSERT INTO access_grants VALUES (1, 102, '2023-01-01');
INSERT INTO access_grants VALUES (1, 103, '2023-01-01');

-- Bob gets 3 high sensitivity resources (Winner)
INSERT INTO access_grants VALUES (2, 101, '2023-01-01');
INSERT INTO access_grants VALUES (2, 102, '2023-01-01');
INSERT INTO access_grants VALUES (2, 104, '2023-01-01');
INSERT INTO access_grants VALUES (2, 103, '2023-01-01');

-- Charlie gets 4, but is in Engineering
INSERT INTO access_grants VALUES (3, 101, '2023-01-01');
INSERT INTO access_grants VALUES (3, 102, '2023-01-01');
INSERT INTO access_grants VALUES (3, 104, '2023-01-01');
INSERT INTO access_grants VALUES (3, 105, '2023-01-01');

-- Diana gets 1
INSERT INTO access_grants VALUES (4, 104, '2023-01-01');
EOF

    chmod -R 777 /home/user
