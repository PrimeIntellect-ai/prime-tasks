#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user

    # Create SQLite DB
    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE departments(id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER);
CREATE TABLE permissions(dept_id INTEGER, resource_id INTEGER, can_read INTEGER, can_write INTEGER);

INSERT INTO departments VALUES (10, 'Engineering');
INSERT INTO departments VALUES (20, 'HR');

INSERT INTO users VALUES (1, 'Alice', 10);
INSERT INTO users VALUES (2, 'Bob', 20);
INSERT INTO users VALUES (3, 'Charlie', 10);

INSERT INTO permissions VALUES (10, 100, 1, 1);
INSERT INTO permissions VALUES (10, 200, 1, 0);
INSERT INTO permissions VALUES (20, 200, 1, 0);
INSERT INTO permissions VALUES (20, 300, 1, 1);
EOF

    # Create JSON logs
    cat <<EOF > /home/user/logs.json
[
  {"timestamp": "2023-10-01T10:00:00Z", "user_id": 1, "resource_id": 100, "action": "READ"},
  {"timestamp": "2023-10-01T10:05:00Z", "user_id": 3, "resource_id": 200, "action": "WRITE"},
  {"timestamp": "2023-10-01T10:10:00Z", "user_id": 1, "resource_id": 300, "action": "READ"},
  {"timestamp": "2023-10-01T10:15:00Z", "user_id": 2, "resource_id": 300, "action": "WRITE"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
