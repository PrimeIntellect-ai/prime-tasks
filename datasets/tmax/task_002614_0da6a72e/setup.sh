#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak ffmpeg
    pip3 install --default-timeout=100 pytest

    mkdir -p /app
    sqlite3 /app/company.db <<EOF
CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, status TEXT);
INSERT INTO employees VALUES (101, 'Alice', 'active');
INSERT INTO employees VALUES (102, 'Bob', 'inactive');
INSERT INTO employees VALUES (103, 'Charlie', 'active');
INSERT INTO employees VALUES (104, 'Diana', 'active');

CREATE TABLE employee_edges (source_id INTEGER, target_id INTEGER);
INSERT INTO employee_edges VALUES (101, 103);
INSERT INTO employee_edges VALUES (103, 104);

CREATE INDEX idx_status ON employees(status);
EOF

    espeak -w /tmp/temp.wav "Add an edge from employee 104 to employee 101."
    ffmpeg -i /tmp/temp.wav -ar 16000 /app/overrides.wav
    rm /tmp/temp.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
