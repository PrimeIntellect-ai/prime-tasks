#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 rustc cargo libsqlite3-dev pkg-config build-essential
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    sqlite3 backup_metadata.db <<EOF
CREATE TABLE backups (
    id INTEGER PRIMARY KEY,
    server_name TEXT,
    backup_type TEXT,
    parent_id INTEGER,
    size_bytes INTEGER,
    created_at DATETIME
);

INSERT INTO backups VALUES (1, 'db-prod-1', 'FULL', NULL, 10737418240, '2023-10-01 00:00:00');
INSERT INTO backups VALUES (2, 'db-prod-2', 'FULL', NULL, 8589934592, '2023-10-01 01:00:00');
INSERT INTO backups VALUES (3, 'db-prod-1', 'INC', 1, 524288000, '2023-10-02 00:00:00');
INSERT INTO backups VALUES (4, 'db-prod-1', 'INC', 3, 209715200, '2023-10-03 00:00:00');
INSERT INTO backups VALUES (5, 'db-prod-2', 'INC', 2, 104857600, '2023-10-02 01:00:00');
INSERT INTO backups VALUES (6, 'db-prod-1', 'INC', 4, 314572800, '2023-10-04 00:00:00');
INSERT INTO backups VALUES (7, 'db-prod-1', 'FULL', NULL, 11811160064, '2023-10-05 00:00:00');
INSERT INTO backups VALUES (8, 'db-prod-1', 'INC', 7, 10485760, '2023-10-06 00:00:00');
INSERT INTO backups VALUES (9, 'db-prod-1', 'INC', 8, 5242880, '2023-10-07 00:00:00');
INSERT INTO backups VALUES (10, 'db-prod-1', 'INC', 9, 7340032, '2023-10-08 00:00:00');
INSERT INTO backups VALUES (11, 'db-prod-1', 'INC', 10, 2097152, '2023-10-09 00:00:00');
INSERT INTO backups VALUES (12, 'db-prod-1', 'INC', 11, 4194304, '2023-10-10 00:00:00');
INSERT INTO backups VALUES (13, 'db-prod-1', 'INC', 12, 1048576, '2023-10-11 00:00:00');
INSERT INTO backups VALUES (14, 'db-prod-1', 'INC', 13, 8388608, '2023-10-12 00:00:00');
INSERT INTO backups VALUES (15, 'db-prod-1', 'INC', 14, 1572864, '2023-10-13 00:00:00');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
