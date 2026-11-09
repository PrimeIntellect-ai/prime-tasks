#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE backups (id INTEGER PRIMARY KEY, name TEXT, size_mb INTEGER);
CREATE TABLE dependencies (id INTEGER, parent_id INTEGER);
INSERT INTO backups VALUES (1, 'Full_A', 1000);
INSERT INTO backups VALUES (2, 'Inc_A1', 100);
INSERT INTO backups VALUES (3, 'Inc_A2', 50);
INSERT INTO backups VALUES (4, 'Full_B', 2000);
INSERT INTO backups VALUES (5, 'Inc_B1', 200);
INSERT INTO backups VALUES (6, 'Inc_B2', 150);
INSERT INTO backups VALUES (7, 'Inc_B3', 300);
INSERT INTO dependencies VALUES (2, 1);
INSERT INTO dependencies VALUES (3, 2);
INSERT INTO dependencies VALUES (5, 4);
INSERT INTO dependencies VALUES (6, 5);
INSERT INTO dependencies VALUES (7, 6);
EOF

    cat <<EOF > /home/user/targets.txt
Inc_A2
Inc_B3
Full_A
Full_B
Inc_B1
EOF

    chmod -R 777 /home/user
