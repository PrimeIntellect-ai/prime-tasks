#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest jsonschema

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE jobs (id TEXT PRIMARY KEY, parent_id TEXT, size_bytes INTEGER, start_time DATETIME);
INSERT INTO jobs VALUES ('BKP-001', NULL, 1000, '2023-10-01 10:00:00');
INSERT INTO jobs VALUES ('BKP-002', 'BKP-001', 500, '2023-10-01 10:05:00');
INSERT INTO jobs VALUES ('BKP-003', 'BKP-001', 750, '2023-10-01 10:10:00');
INSERT INTO jobs VALUES ('BKP-004', 'BKP-002', 200, '2023-10-01 10:15:00');
INSERT INTO jobs VALUES ('BKP-005', 'BKP-003', 100, '2023-10-01 10:20:00');
INSERT INTO jobs VALUES ('BKP-006', 'BKP-009', 5000, '2023-10-01 10:25:00');
EOF

    chmod -R 777 /home/user
