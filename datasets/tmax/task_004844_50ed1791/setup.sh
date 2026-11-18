#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc sqlite3 git
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE assets (id INTEGER PRIMARY KEY, name TEXT, type TEXT, is_corrupted INTEGER);
CREATE TABLE links (src INTEGER, dst INTEGER, status TEXT);

INSERT INTO assets VALUES (1, 'db-prod-main', 'database', 1);
INSERT INTO assets VALUES (2, 'db-users', 'database', 0);
INSERT INTO assets VALUES (3, 'job-prod-daily', 'job', 0);
INSERT INTO assets VALUES (4, 'job-prod-weekly', 'job', 0);
INSERT INTO assets VALUES (5, 'job-users-daily', 'job', 0);
INSERT INTO assets VALUES (6, 'san-primary', 'storage', 0);
INSERT INTO assets VALUES (7, 's3-archive', 'storage', 0);
INSERT INTO assets VALUES (8, 'tape-vault', 'storage', 0);
INSERT INTO assets VALUES (9, 'san-secondary', 'storage', 0);
INSERT INTO assets VALUES (10, 'db-prod-metrics', 'database', 1);
INSERT INTO assets VALUES (11, 'job-metrics-hourly', 'job', 0);
INSERT INTO assets VALUES (12, 's3-metrics', 'storage', 0);
INSERT INTO assets VALUES (13, 's3-isolated', 'storage', 0);

INSERT INTO links VALUES (1, 3, 'active');
INSERT INTO links VALUES (1, 4, 'active');
INSERT INTO links VALUES (2, 5, 'active');
INSERT INTO links VALUES (3, 6, 'active');
INSERT INTO links VALUES (4, 7, 'active');
INSERT INTO links VALUES (6, 8, 'active');
INSERT INTO links VALUES (5, 9, 'active');
INSERT INTO links VALUES (10, 11, 'active');
INSERT INTO links VALUES (11, 12, 'active');

-- Stale links that shouldn't be traversed
INSERT INTO links VALUES (1, 5, 'stale');
INSERT INTO links VALUES (2, 3, 'stale');
INSERT INTO links VALUES (4, 13, 'stale');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
