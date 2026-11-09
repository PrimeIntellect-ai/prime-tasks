#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backups.db <<'EOF'
CREATE TABLE backup_jobs (
    id INTEGER PRIMARY KEY,
    job_type TEXT,
    parent_id INTEGER,
    status TEXT,
    size_bytes INTEGER,
    timestamp INTEGER
);

-- Chain 1 (Valid total: 100 + 10 + 15 = 125)
INSERT INTO backup_jobs VALUES (1, 'FULL', NULL, 'SUCCESS', 100, 1600000000);
INSERT INTO backup_jobs VALUES (2, 'INC', 1, 'SUCCESS', 10, 1600000001);
INSERT INTO backup_jobs VALUES (3, 'INC', 2, 'SUCCESS', 15, 1600000002);

-- Chain 2 (Valid total: 150. Backup 5 failed, so 6 is orphaned/invalid)
INSERT INTO backup_jobs VALUES (4, 'FULL', NULL, 'SUCCESS', 150, 1600000010);
INSERT INTO backup_jobs VALUES (5, 'INC', 4, 'FAILED', 20, 1600000011);
INSERT INTO backup_jobs VALUES (6, 'INC', 5, 'SUCCESS', 500, 1600000012);

-- Chain 3 (Valid total: 90 + 40 + 30 = 160) - LARGEST VALID CHAIN
INSERT INTO backup_jobs VALUES (7, 'FULL', NULL, 'SUCCESS', 90, 1600000020);
INSERT INTO backup_jobs VALUES (8, 'INC', 7, 'SUCCESS', 40, 1600000021);
INSERT INTO backup_jobs VALUES (9, 'INC', 8, 'SUCCESS', 30, 1600000022);

-- Chain 4 (Failed FULL backup, valid total: 0)
INSERT INTO backup_jobs VALUES (10, 'FULL', NULL, 'FAILED', 200, 1600000030);
INSERT INTO backup_jobs VALUES (11, 'INC', 10, 'SUCCESS', 50, 1600000031);
EOF

    chmod -R 777 /home/user
