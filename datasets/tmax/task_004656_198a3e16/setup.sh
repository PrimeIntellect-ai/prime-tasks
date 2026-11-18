#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT);
CREATE TABLE jobs (
    id INTEGER PRIMARY KEY,
    server_id INTEGER,
    status TEXT,
    duration_sec INTEGER
);
CREATE TABLE deps (
    job_id INTEGER,
    depends_on INTEGER
);

INSERT INTO servers VALUES (1, 'db-prod'), (2, 'web-prod'), (3, 'cache-prod');

INSERT INTO jobs VALUES 
(1, 1, 'SUCCESS', 1000),
(2, 1, 'SUCCESS', 1500),
(3, 1, 'SUCCESS', 800),
(4, 1, 'FAILED', 2000),
(5, 2, 'SUCCESS', 500),
(6, 2, 'SUCCESS', 600),
(7, 2, 'SUCCESS', 400),
(8, 3, 'SUCCESS', 100),
(9, 3, 'SUCCESS', 120),
(10, 3, 'SUCCESS', 90),
(11, 1, 'FAILED', 100),
(12, 1, 'FAILED', 200),
(13, 1, 'FAILED', 300),
(14, 1, 'FAILED', 400);

INSERT INTO deps VALUES 
(14, 13),
(13, 11),
(11, 4),
(4, 2);
EOF

    chmod -R 777 /home/user
