#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    sqlite3 backup_catalog.db <<EOF
CREATE TABLE jobs (
    id INTEGER PRIMARY KEY,
    type TEXT,
    status TEXT,
    start_time INTEGER
);

CREATE TABLE files (
    id INTEGER PRIMARY KEY,
    job_id INTEGER,
    size_bytes INTEGER
);

-- Old successful full backup
INSERT INTO jobs (id, type, status, start_time) VALUES (1, 'full', 'success', 1600000000);
INSERT INTO files (job_id, size_bytes) VALUES (1, 50000);

-- Old successful inc
INSERT INTO jobs (id, type, status, start_time) VALUES (2, 'inc', 'success', 1600086400);
INSERT INTO files (job_id, size_bytes) VALUES (2, 500);

-- Failed full backup
INSERT INTO jobs (id, type, status, start_time) VALUES (3, 'full', 'failed', 1600172800);

-- Most recent successful full backup (Target)
INSERT INTO jobs (id, type, status, start_time) VALUES (4, 'full', 'success', 1600259200);
INSERT INTO files (job_id, size_bytes) VALUES (4, 60000);

-- Failed inc
INSERT INTO jobs (id, type, status, start_time) VALUES (5, 'inc', 'failed', 1600345600);
INSERT INTO files (job_id, size_bytes) VALUES (5, 600);

-- Successful inc 1 (Target)
INSERT INTO jobs (id, type, status, start_time) VALUES (6, 'inc', 'success', 1600432000);
INSERT INTO files (job_id, size_bytes) VALUES (6, 1200);

-- Successful inc 2 (Target)
INSERT INTO jobs (id, type, status, start_time) VALUES (7, 'inc', 'success', 1600518400);
INSERT INTO files (job_id, size_bytes) VALUES (7, 800);
EOF

    chmod -R 777 /home/user
