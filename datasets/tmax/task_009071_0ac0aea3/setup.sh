#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    # Create the SQLite database
    sqlite3 corp_auth.db << 'EOF'
CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER);
CREATE TABLE departments (dept_id INTEGER PRIMARY KEY, dept_name TEXT, parent_dept_id INTEGER);
CREATE TABLE resource_policies (resource_id TEXT PRIMARY KEY, required_dept_id INTEGER);

INSERT INTO departments VALUES (1, 'Corp', NULL);
INSERT INTO departments VALUES (2, 'Engineering', 1);
INSERT INTO departments VALUES (3, 'HR', 1);
INSERT INTO departments VALUES (4, 'Backend', 2);
INSERT INTO departments VALUES (5, 'Frontend', 2);
INSERT INTO departments VALUES (6, 'Recruiting', 3);

INSERT INTO employees VALUES (101, 'Alice', 1);
INSERT INTO employees VALUES (102, 'Bob', 2);
INSERT INTO employees VALUES (103, 'Charlie', 4);
INSERT INTO employees VALUES (104, 'Diana', 6);

INSERT INTO resource_policies VALUES ('RES-A', 1);
INSERT INTO resource_policies VALUES ('RES-B', 2);
INSERT INTO resource_policies VALUES ('RES-C', 4);
INSERT INTO resource_policies VALUES ('RES-D', 3);
EOF

    # Create the access requests file
    cat << 'EOF' > access_requests.txt
101,RES-A
102,RES-A
103,RES-A
104,RES-B
102,RES-B
103,RES-B
102,RES-C
103,RES-C
104,RES-C
101,RES-D
EOF

    chmod -R 777 /home/user
