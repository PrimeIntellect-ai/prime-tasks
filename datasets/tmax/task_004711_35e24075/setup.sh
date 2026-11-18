#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE users (user_id INTEGER PRIMARY KEY, username TEXT);
CREATE TABLE roles (role_id INTEGER PRIMARY KEY, role_name TEXT);
CREATE TABLE user_roles (user_id INTEGER, role_id INTEGER);
CREATE TABLE role_inheritance (parent_role_id INTEGER, child_role_id INTEGER);
CREATE TABLE role_permissions (role_id INTEGER, resource_name TEXT);
CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, timestamp DATETIME, user_id INTEGER, resource_name TEXT);

-- Create the "corrupt" index
CREATE INDEX idx_logs_time ON access_logs(timestamp);

INSERT INTO users VALUES (1, 'alice'), (2, 'bob'), (3, 'charlie'), (4, 'david');
INSERT INTO roles VALUES (10, 'admin'), (11, 'editor'), (12, 'viewer'), (13, 'guest');

-- user roles
INSERT INTO user_roles VALUES (1, 10), (2, 11), (3, 12), (4, 13);

-- inheritance: admin inherits editor, editor inherits viewer, viewer inherits guest
INSERT INTO role_inheritance VALUES (10, 11), (11, 12), (12, 13);

-- permissions
INSERT INTO role_permissions VALUES (10, 'system_config');
INSERT INTO role_permissions VALUES (11, 'edit_articles');
INSERT INTO role_permissions VALUES (12, 'view_articles');
INSERT INTO role_permissions VALUES (13, 'public_landing');

-- logs
-- valid logs (alice can access anything due to inheritance, bob can access edit, view, landing)
INSERT INTO access_logs VALUES (100, '2023-10-01 10:00:00', 1, 'system_config');
INSERT INTO access_logs VALUES (101, '2023-10-01 10:05:00', 1, 'view_articles');
INSERT INTO access_logs VALUES (102, '2023-10-01 10:10:00', 2, 'view_articles');
INSERT INTO access_logs VALUES (103, '2023-10-01 10:15:00', 3, 'public_landing');

-- invalid logs
-- bob tries system config (3 times, we only want 2 most recent)
INSERT INTO access_logs VALUES (104, '2023-10-01 11:00:00', 2, 'system_config');
INSERT INTO access_logs VALUES (105, '2023-10-01 11:05:00', 2, 'system_config');
INSERT INTO access_logs VALUES (106, '2023-10-01 11:10:00', 2, 'system_config');

-- charlie tries edit (1 time)
INSERT INTO access_logs VALUES (107, '2023-10-01 11:15:00', 3, 'edit_articles');

-- david tries view (3 times)
INSERT INTO access_logs VALUES (108, '2023-10-01 11:20:00', 4, 'view_articles');
INSERT INTO access_logs VALUES (109, '2023-10-01 11:25:00', 4, 'view_articles');
INSERT INTO access_logs VALUES (110, '2023-10-01 11:30:00', 4, 'view_articles');
EOF

    chmod -R 777 /home/user
