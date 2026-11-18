#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang build-essential
    pip3 install pytest

    mkdir -p /home/user/audit
    cd /home/user
    sqlite3 audit.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE groups (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE group_members (employee_id INTEGER, group_id INTEGER);
CREATE TABLE group_hierarchy (parent_group_id INTEGER, child_group_id INTEGER);
CREATE TABLE access_policies (group_id INTEGER, resource_name TEXT, access_level TEXT);

INSERT INTO employees VALUES (1, 'Alice');
INSERT INTO employees VALUES (2, 'Bob');
INSERT INTO employees VALUES (3, 'Charlie');
INSERT INTO employees VALUES (4, 'Dave');
INSERT INTO employees VALUES (5, 'Eve');
INSERT INTO employees VALUES (6, 'Frank');

INSERT INTO groups VALUES (10, 'Dev');
INSERT INTO groups VALUES (20, 'Ops');
INSERT INTO groups VALUES (30, 'Finance');
INSERT INTO groups VALUES (40, 'Management');
INSERT INTO groups VALUES (50, 'Directors');
INSERT INTO groups VALUES (60, 'HR');

INSERT INTO group_hierarchy VALUES (30, 60);
INSERT INTO group_hierarchy VALUES (40, 30);
INSERT INTO group_hierarchy VALUES (50, 40);

INSERT INTO access_policies VALUES (10, 'DEV_SERVER', 'ADMIN');
INSERT INTO access_policies VALUES (30, 'FINANCIAL_RECORDS', 'WRITE');
INSERT INTO access_policies VALUES (50, 'FINANCIAL_RECORDS', 'ADMIN');
INSERT INTO access_policies VALUES (20, 'FINANCIAL_RECORDS', 'READ');

INSERT INTO group_members VALUES (1, 10);
INSERT INTO group_members VALUES (2, 30);
INSERT INTO group_members VALUES (3, 60);
INSERT INTO group_members VALUES (4, 40);
INSERT INTO group_members VALUES (5, 50);
INSERT INTO group_members VALUES (6, 20);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
