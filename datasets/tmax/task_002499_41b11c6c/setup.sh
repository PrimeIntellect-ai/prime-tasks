#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backup_topology.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, hostname TEXT);
CREATE TABLE edges (source_id INTEGER, target_id INTEGER);
INSERT INTO nodes VALUES (1, 'main-db-server');
INSERT INTO nodes VALUES (2, 'cache-server');
INSERT INTO nodes VALUES (3, 'backup-tier-1');
INSERT INTO nodes VALUES (4, 'backup-tier-2');
INSERT INTO nodes VALUES (5, 'offsite-archive');
INSERT INTO nodes VALUES (6, 'tape-storage');
INSERT INTO nodes VALUES (7, 'isolated-backup');

INSERT INTO edges VALUES (1, 3);
INSERT INTO edges VALUES (3, 4);
INSERT INTO edges VALUES (4, 5);
INSERT INTO edges VALUES (4, 6);
INSERT INTO edges VALUES (2, 7);

CREATE INDEX idx_edges_source ON edges(source_id);
EOF

    chmod -R 777 /home/user
