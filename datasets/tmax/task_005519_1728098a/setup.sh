#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Setup the SQLite database
    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE group_members (emp_id INTEGER, group_id INTEGER);
CREATE TABLE group_access (group_id INTEGER, system_id INTEGER, system_name TEXT);

INSERT INTO employees VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');
INSERT INTO group_members VALUES (1, 100), (1, 101), (2, 100);
INSERT INTO group_access VALUES (100, 50, 'Finance'), (101, 51, 'HR'), (102, 52, 'IT');
EOF
    sqlite3 /home/user/audit.db < /home/user/setup_db.sql
    rm /home/user/setup_db.sql

    chmod -R 777 /home/user
