#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE users (uid INTEGER PRIMARY KEY, username TEXT, dept TEXT);
CREATE TABLE assets (aid INTEGER PRIMARY KEY, asset_name TEXT, classification_level INTEGER);
CREATE TABLE data_flows (source_aid INTEGER, dest_aid INTEGER);
CREATE TABLE audit_log (log_id INTEGER PRIMARY KEY, uid INTEGER, aid INTEGER, timestamp DATETIME);

INSERT INTO users VALUES (1, 'alice', 'IT'), (2, 'bob', 'HR'), (3, 'charlie', 'Finance');
INSERT INTO assets VALUES (10, 'PublicWeb', 1), (11, 'InternalPortal', 2), (12, 'CustomerDB', 4), (13, 'PaymentGateway', 5);

INSERT INTO data_flows VALUES (10, 11), (11, 12), (12, 13), (13, 11);

INSERT INTO audit_log VALUES (100, 1, 10, '2023-10-01 10:00:00');
INSERT INTO audit_log VALUES (101, 2, 11, '2023-10-01 10:05:00');
INSERT INTO audit_log VALUES (102, 3, 12, '2023-10-01 10:10:00');
INSERT INTO audit_log VALUES (103, 1, 13, '2023-10-01 10:15:00');
INSERT INTO audit_log VALUES (104, 2, 10, '2023-10-01 10:20:00');
EOF

    chmod -R 777 /home/user
