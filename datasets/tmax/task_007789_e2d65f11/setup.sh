#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    # Create the SQLite database with the hidden schema
    sqlite3 corp_audit.db <<EOF
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    username TEXT UNIQUE
);

CREATE TABLE groups (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE
);

CREATE TABLE resources (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE,
    classification TEXT
);

CREATE TABLE user_groups (
    user_id INTEGER,
    group_id INTEGER,
    FOREIGN KEY(user_id) REFERENCES users(id),
    FOREIGN KEY(group_id) REFERENCES groups(id)
);

CREATE TABLE group_nesting (
    child_group_id INTEGER,
    parent_group_id INTEGER,
    FOREIGN KEY(child_group_id) REFERENCES groups(id),
    FOREIGN KEY(parent_group_id) REFERENCES groups(id)
);

CREATE TABLE group_resources (
    group_id INTEGER,
    resource_id INTEGER,
    FOREIGN KEY(group_id) REFERENCES groups(id),
    FOREIGN KEY(resource_id) REFERENCES resources(id)
);

-- Insert Users
INSERT INTO users (id, username) VALUES (1, 'Alice');
INSERT INTO users (id, username) VALUES (2, 'Bob');
INSERT INTO users (id, username) VALUES (3, 'Charlie');
INSERT INTO users (id, username) VALUES (4, 'Mallory');

-- Insert Groups
INSERT INTO groups (id, name) VALUES (10, 'Interns');
INSERT INTO groups (id, name) VALUES (11, 'Dev_Team');
INSERT INTO groups (id, name) VALUES (12, 'Engineering');
INSERT INTO groups (id, name) VALUES (13, 'SuperAdmins');
INSERT INTO groups (id, name) VALUES (14, 'HR');
INSERT INTO groups (id, name) VALUES (15, 'All_Staff');

-- Insert Resources
INSERT INTO resources (id, name, classification) VALUES (100, 'Project_Apollo_Secrets', 'Top Secret');
INSERT INTO resources (id, name, classification) VALUES (101, 'Financial_Q4_Report', 'Confidential');
INSERT INTO resources (id, name, classification) VALUES (102, 'Public_Share', 'Public');

-- User Group Memberships
INSERT INTO user_groups (user_id, group_id) VALUES (4, 10); -- Mallory in Interns
INSERT INTO user_groups (user_id, group_id) VALUES (2, 14); -- Bob in HR

-- Group Nesting (Child inherits Parent's access)
INSERT INTO group_nesting (child_group_id, parent_group_id) VALUES (10, 11); -- Interns -> Dev_Team
INSERT INTO group_nesting (child_group_id, parent_group_id) VALUES (11, 12); -- Dev_Team -> Engineering
INSERT INTO group_nesting (child_group_id, parent_group_id) VALUES (12, 13); -- Engineering -> SuperAdmins (The misconfiguration)
INSERT INTO group_nesting (child_group_id, parent_group_id) VALUES (14, 15); -- HR -> All_Staff

-- Resource Access
INSERT INTO group_resources (group_id, resource_id) VALUES (13, 100); -- SuperAdmins -> Project_Apollo_Secrets
INSERT INTO group_resources (group_id, resource_id) VALUES (15, 101); -- All_Staff -> Financial_Q4_Report
EOF

    chmod -R 777 /home/user
