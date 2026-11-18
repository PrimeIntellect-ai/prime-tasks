#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backups.db << 'EOF'
CREATE TABLE backup_metadata (
    backup_id TEXT PRIMARY KEY,
    backup_type TEXT,
    size_bytes INTEGER
);
CREATE TABLE backup_lineage (
    parent_id TEXT,
    child_id TEXT
);
INSERT INTO backup_metadata VALUES ('bkp_001', 'full', 104857600);
INSERT INTO backup_metadata VALUES ('bkp_002', 'incremental', 15728640);
INSERT INTO backup_metadata VALUES ('bkp_003', 'incremental', 5242880);
INSERT INTO backup_metadata VALUES ('bkp_004', 'incremental', 2097152);
INSERT INTO backup_metadata VALUES ('bkp_005', 'incremental', 8388608);

INSERT INTO backup_lineage VALUES ('bkp_001', 'bkp_002');
INSERT INTO backup_lineage VALUES ('bkp_002', 'bkp_003');
INSERT INTO backup_lineage VALUES ('bkp_003', 'bkp_004');
INSERT INTO backup_lineage VALUES ('bkp_004', 'bkp_005');
EOF

    chmod -R 777 /home/user
