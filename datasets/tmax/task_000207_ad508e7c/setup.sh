#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE backups(id INTEGER PRIMARY KEY, parent_id INTEGER, size_bytes INTEGER, status TEXT);

-- Valid chain 1
INSERT INTO backups VALUES(1, NULL, 1000, 'active');
INSERT INTO backups VALUES(2, 1, 500, 'active');
INSERT INTO backups VALUES(3, 2, 200, 'active');

-- Orphaned chain (Root is deleted)
INSERT INTO backups VALUES(4, NULL, 2000, 'deleted');
INSERT INTO backups VALUES(5, 4, 300, 'active');
INSERT INTO backups VALUES(6, 5, 100, 'active');

-- Orphaned chain (Root is missing entirely)
INSERT INTO backups VALUES(7, 999, 400, 'active');
INSERT INTO backups VALUES(8, 7, 150, 'active');

-- Valid chain 2
INSERT INTO backups VALUES(9, NULL, 5000, 'active');
INSERT INTO backups VALUES(10, 9, 250, 'active');

-- Orphaned because it's a deleted node in an otherwise valid chain (we only sum active orphans, but wait, this itself is deleted so size is not counted)
INSERT INTO backups VALUES(11, 10, 300, 'deleted');

-- Orphaned chain (Loop)
INSERT INTO backups VALUES(12, 13, 600, 'active');
INSERT INTO backups VALUES(13, 12, 600, 'active');
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
