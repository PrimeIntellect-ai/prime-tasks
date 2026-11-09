#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE backups (id TEXT, db_name TEXT, backup_type TEXT, parent_id TEXT, ts INTEGER);
INSERT INTO backups VALUES ('b1', 'db_prod', 'full', '', 1000);
INSERT INTO backups VALUES ('b2', 'db_prod', 'incremental', 'b1', 1010);
INSERT INTO backups VALUES ('b3', 'db_prod', 'incremental', 'b2', 1020);
INSERT INTO backups VALUES ('b4', 'db_prod', 'full', '', 1050);
INSERT INTO backups VALUES ('b5', 'db_prod', 'incremental', 'b4', 1060);
INSERT INTO backups VALUES ('b6', 'db_dev', 'full', '', 1005);
INSERT INTO backups VALUES ('b7', 'db_dev', 'incremental', 'b6', 1015);
EOF

    chmod -R 777 /home/user
