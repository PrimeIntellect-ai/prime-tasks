#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/pipeline.db <<EOF
CREATE TABLE assets (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER);
INSERT INTO assets VALUES (1, 'Root', NULL);
INSERT INTO assets VALUES (2, 'Node_A', 1);
INSERT INTO assets VALUES (3, 'Node_B', 1);
INSERT INTO assets VALUES (4, 'Node_AA', 2);
INSERT INTO assets VALUES (5, 'Node_AB', 2);
INSERT INTO assets VALUES (6, 'Node_AAA', 4);
INSERT INTO assets VALUES (7, 'Node_AAAA', 6);
INSERT INTO assets VALUES (8, 'Node_C', 1);
CREATE INDEX idx_parent ON assets(parent_id);
EOF

    sqlite3 /home/user/pipeline.db "PRAGMA writable_schema = 1; DELETE FROM sqlite_schema WHERE type='index' AND name='idx_parent'; PRAGMA writable_schema = 0;"

    chmod -R 777 /home/user
