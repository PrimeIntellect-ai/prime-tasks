#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo rustc libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user
    sqlite3 /home/user/compliance.db << 'EOF'
CREATE TABLE users (user_id TEXT, base_role TEXT);
CREATE TABLE role_graph (parent_role TEXT, child_role TEXT);
CREATE TABLE events (event_id INTEGER, timestamp INTEGER, user_id TEXT, role_assumed TEXT, status TEXT);

INSERT INTO users VALUES ('u1', 'guest'), ('u2', 'manager'), ('u3', 'employee');

INSERT INTO role_graph VALUES 
('admin', 'manager'),
('manager', 'employee'),
('employee', 'guest');

-- u1 (guest) tries to get admin, fails 3 times, succeeds (FLAGGED)
INSERT INTO events VALUES (1, 100, 'u1', 'admin', 'FAILURE');
INSERT INTO events VALUES (2, 101, 'u1', 'admin', 'FAILURE');
INSERT INTO events VALUES (3, 102, 'u1', 'admin', 'FAILURE');
INSERT INTO events VALUES (4, 103, 'u1', 'admin', 'SUCCESS');

-- u2 (manager) tries to get employee, fails 3 times, succeeds (REACHABLE, NOT FLAGGED)
INSERT INTO events VALUES (5, 110, 'u2', 'employee', 'FAILURE');
INSERT INTO events VALUES (6, 111, 'u2', 'employee', 'FAILURE');
INSERT INTO events VALUES (7, 112, 'u2', 'employee', 'FAILURE');
INSERT INTO events VALUES (8, 113, 'u2', 'employee', 'SUCCESS');

-- u3 (employee) tries to get admin, fails 2 times, succeeds (UNREACHABLE, BUT ONLY 2 FAILURES, NOT FLAGGED)
INSERT INTO events VALUES (9, 120, 'u3', 'admin', 'FAILURE');
INSERT INTO events VALUES (10, 121, 'u3', 'admin', 'FAILURE');
INSERT INTO events VALUES (11, 122, 'u3', 'admin', 'SUCCESS');

-- u1 (guest) tries to get manager, fails 4 times, succeeds (FLAGGED)
INSERT INTO events VALUES (12, 130, 'u1', 'manager', 'FAILURE');
INSERT INTO events VALUES (13, 131, 'u1', 'manager', 'FAILURE');
INSERT INTO events VALUES (14, 132, 'u1', 'manager', 'FAILURE');
INSERT INTO events VALUES (15, 133, 'u1', 'manager', 'FAILURE');
INSERT INTO events VALUES (16, 134, 'u1', 'manager', 'SUCCESS');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
