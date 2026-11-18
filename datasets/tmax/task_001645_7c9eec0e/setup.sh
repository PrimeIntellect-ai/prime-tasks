#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/dag.db <<EOF
CREATE TABLE tasks (id INTEGER PRIMARY KEY, parent_id INTEGER, duration INTEGER);

INSERT INTO tasks (id, parent_id, duration) VALUES (1, NULL, 10);
INSERT INTO tasks (id, parent_id, duration) VALUES (2, 1, 15);
INSERT INTO tasks (id, parent_id, duration) VALUES (3, 1, 20);
INSERT INTO tasks (id, parent_id, duration) VALUES (4, 2, 40);
INSERT INTO tasks (id, parent_id, duration) VALUES (5, 2, 10);
INSERT INTO tasks (id, parent_id, duration) VALUES (6, 3, 50);
INSERT INTO tasks (id, parent_id, duration) VALUES (7, 3, 5);
INSERT INTO tasks (id, parent_id, duration) VALUES (8, 6, 30);
INSERT INTO tasks (id, parent_id, duration) VALUES (9, 6, 10);
INSERT INTO tasks (id, parent_id, duration) VALUES (10, 8, 25);
INSERT INTO tasks (id, parent_id, duration) VALUES (11, 4, 60);

-- Create a "corrupted" index by creating an index then manually messing with sqlite_master
CREATE INDEX idx_parent ON tasks(parent_id);
PRAGMA writable_schema = ON;
UPDATE sqlite_master SET sql = 'CREATE INDEX idx_parent ON tasks(duration)' WHERE type = 'index' AND name = 'idx_parent';
PRAGMA writable_schema = OFF;
EOF

    chmod -R 777 /home/user
