#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE backups (
    id INTEGER PRIMARY KEY,
    backup_name TEXT UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE restore_links (
    parent_id INTEGER,
    child_id INTEGER,
    FOREIGN KEY(parent_id) REFERENCES backups(id),
    FOREIGN KEY(child_id) REFERENCES backups(id)
);

INSERT INTO backups (id, backup_name) VALUES 
(1, 'full_base_001'),
(2, 'diff_001'),
(3, 'incr_002'),
(4, 'incr_003'),
(5, 'incr_004'),
(6, 'incr_log_999'),
(7, 'orphan_log'),
(8, 'shortcut_diff');

-- Chain 1 (Length 5): 1 -> 3 -> 4 -> 5 -> 6
INSERT INTO restore_links (parent_id, child_id) VALUES (1, 3), (3, 4), (4, 5), (5, 6);

-- Chain 2 (Length 3): 1 -> 8 -> 6 (This is the shortest path!)
INSERT INTO restore_links (parent_id, child_id) VALUES (1, 8), (8, 6);

-- Noise
INSERT INTO restore_links (parent_id, child_id) VALUES (1, 2), (2, 7);
EOF

    sqlite3 /home/user/backup_metadata.db < /tmp/setup_db.sql
    rm /tmp/setup_db.sql

    chmod -R 777 /home/user
