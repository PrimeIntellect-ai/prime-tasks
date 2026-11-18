#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task dependencies
    apt-get install -y sqlite3 libsqlite3-dev gcc

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directory and setup database
    mkdir -p /home/user
    cd /home/user

    sqlite3 backups.db <<EOF
CREATE TABLE backup_metadata (id TEXT PRIMARY KEY, type TEXT, size_mb INTEGER, timestamp INTEGER);
INSERT INTO backup_metadata VALUES ('bkp_100', 'FULL', 5000, 1600000000);
INSERT INTO backup_metadata VALUES ('bkp_101', 'INC', 250, 1600086400);
INSERT INTO backup_metadata VALUES ('bkp_102', 'INC', 120, 1600172800);
INSERT INTO backup_metadata VALUES ('bkp_103', 'INC', 300, 1600259200);
INSERT INTO backup_metadata VALUES ('bkp_104', 'INC', 150, 1600345600);
INSERT INTO backup_metadata VALUES ('bkp_105', 'INC', 80, 1600432000);
INSERT INTO backup_metadata VALUES ('bkp_106', 'INC', 90, 1600518400);
EOF

    # Set permissions
    chmod -R 777 /home/user
