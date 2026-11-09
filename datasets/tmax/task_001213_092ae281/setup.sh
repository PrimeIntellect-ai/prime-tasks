#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest networkx

    mkdir -p /home/user

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE servers (id INTEGER PRIMARY KEY, name TEXT, size_gb INTEGER);
INSERT INTO servers VALUES (1, 'DB-01', 500);
INSERT INTO servers VALUES (2, 'APP-01', 50);
INSERT INTO servers VALUES (3, 'APP-02', 50);
INSERT INTO servers VALUES (4, 'CACHE-01', 20);
INSERT INTO servers VALUES (5, 'WEB-01', 10);

CREATE TABLE dependencies (src INTEGER, dst INTEGER, is_active INTEGER);
INSERT INTO dependencies VALUES (2, 1, 1);
INSERT INTO dependencies VALUES (3, 1, 1);
INSERT INTO dependencies VALUES (5, 2, 1);
INSERT INTO dependencies VALUES (5, 3, 1);
INSERT INTO dependencies VALUES (2, 4, 1);
INSERT INTO dependencies VALUES (3, 4, 1);
INSERT INTO dependencies VALUES (4, 1, 0); 
INSERT INTO dependencies VALUES (5, 1, 0);

CREATE INDEX idx_active ON dependencies(is_active);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
