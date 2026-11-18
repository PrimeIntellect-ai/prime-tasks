#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE backups (id INTEGER PRIMARY KEY, name TEXT, is_base_backup INTEGER);
CREATE TABLE deps (backup_id INTEGER, depends_on INTEGER);

INSERT INTO backups (id, name, is_base_backup) VALUES 
(1, 'base_001', 1),
(2, 'inc_002', 0),
(3, 'inc_003', 0),
(4, 'inc_004', 0),
(8, 'inc_008', 0),
(15, 'inc_015', 0),
(30, 'inc_030', 0),
(42, 'inc_042', 0);

-- Path 1: 42 -> 30 -> 15 -> 2 -> 1 (Length 4 edges)
INSERT INTO deps (backup_id, depends_on) VALUES (42, 30);
INSERT INTO deps (backup_id, depends_on) VALUES (30, 15);
INSERT INTO deps (backup_id, depends_on) VALUES (15, 2);
INSERT INTO deps (backup_id, depends_on) VALUES (2, 1);

-- Path 2: 42 -> 8 -> 3 -> 1 (Length 3 edges) - SHORTEST PATH
INSERT INTO deps (backup_id, depends_on) VALUES (42, 8);
INSERT INTO deps (backup_id, depends_on) VALUES (8, 3);
INSERT INTO deps (backup_id, depends_on) VALUES (3, 1);

-- Distraction edges / dead ends
INSERT INTO deps (backup_id, depends_on) VALUES (8, 4);
INSERT INTO deps (backup_id, depends_on) VALUES (4, 4); -- cycle
INSERT INTO deps (backup_id, depends_on) VALUES (30, 8);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
