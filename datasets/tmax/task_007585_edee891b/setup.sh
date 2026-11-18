#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.sql
CREATE TABLE users (user_id INTEGER PRIMARY KEY, username TEXT);
CREATE TABLE roles (role_id INTEGER PRIMARY KEY, role_name TEXT);
CREATE TABLE user_roles (user_id INTEGER, role_id INTEGER);
CREATE TABLE role_inheritance (parent_role_id INTEGER, child_role_id INTEGER);
CREATE TABLE role_permissions (role_id INTEGER, permission_name TEXT);

INSERT INTO users (user_id, username) VALUES (1, 'Alice_Admin'), (2, 'Charlie_Compliance');

INSERT INTO roles (role_id, role_name) VALUES 
(10, 'Guest'),
(20, 'Employee'),
(30, 'Auditor'),
(40, 'SysAdmin');

-- Charlie is an Auditor
INSERT INTO user_roles (user_id, role_id) VALUES (2, 30);

-- Hierarchy: Auditor inherits from Employee, Employee inherits from Guest
INSERT INTO role_inheritance (child_role_id, parent_role_id) VALUES 
(30, 20),
(20, 10),
(40, 20);

-- Permissions
INSERT INTO role_permissions (role_id, permission_name) VALUES 
(10, 'VIEW_PUBLIC_PAGES'),
(20, 'INTERNAL_LOGIN'),
(20, 'READ_WIKI'),
(30, 'EXPORT_AUDIT_LOGS'),
(30, 'VIEW_FINANCIALS'),
(40, 'ROOT_ACCESS');

CREATE INDEX idx_user_roles ON user_roles(user_id);
CREATE INDEX idx_inheritance ON role_inheritance(child_role_id);
EOF

    sqlite3 /home/user/audit.db < /tmp/setup.sql

    chmod -R 777 /home/user
