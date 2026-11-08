#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

sqlite3 /home/user/audit.db <<EOF
CREATE TABLE employees (emp_id INT, name TEXT);
CREATE TABLE groups (group_id INT, parent_group_id INT, name TEXT);
CREATE TABLE group_members (emp_id INT, group_id INT);
CREATE TABLE permissions (group_id INT, resource_name TEXT);

INSERT INTO employees VALUES (101, 'Alice_Admin');
INSERT INTO employees VALUES (102, 'Bob_Manager');
INSERT INTO employees VALUES (103, 'Charlie_Staff');
INSERT INTO employees VALUES (104, 'Dave_Contractor');
INSERT INTO employees VALUES (105, 'Eve_Spy');

INSERT INTO groups VALUES (1, NULL, 'Global_Admins');
INSERT INTO groups VALUES (2, 1, 'Finance_Managers');
INSERT INTO groups VALUES (3, 2, 'Finance_Staff');
INSERT INTO groups VALUES (4, NULL, 'IT_Support');
INSERT INTO groups VALUES (5, 4, 'Helpdesk');

INSERT INTO permissions VALUES (1, 'CONFIDENTIAL_FINANCE_RECORDS');
INSERT INTO permissions VALUES (4, 'IT_SYSTEM_LOGS');

INSERT INTO group_members VALUES (101, 1);
INSERT INTO group_members VALUES (102, 2);
INSERT INTO group_members VALUES (103, 3);
INSERT INTO group_members VALUES (104, 5);
EOF

chmod -R 777 /home/user
