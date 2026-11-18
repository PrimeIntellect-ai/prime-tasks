#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT);
CREATE TABLE backups (id INTEGER PRIMARY KEY, server_id INTEGER, parent_id INTEGER, type TEXT, size_bytes INTEGER, created_at DATETIME);

INSERT INTO servers (id, hostname) VALUES (1, 'db-master-42');
INSERT INTO servers (id, hostname) VALUES (2, 'db-replica-01');

-- Setup chain for db-master-42
-- Chain 1 (Old)
INSERT INTO backups VALUES (10, 1, NULL, 'F', 5000000000, '2023-10-01 00:00:00');
INSERT INTO backups VALUES (11, 1, 10, 'I', 150000000, '2023-10-02 00:00:00');

-- Chain 2 (Current)
INSERT INTO backups VALUES (20, 1, NULL, 'F', 5200000000, '2023-10-08 00:00:00');
INSERT INTO backups VALUES (21, 1, 20, 'I', 200000000, '2023-10-09 00:00:00');
INSERT INTO backups VALUES (22, 1, 21, 'I', 250000000, '2023-10-10 00:00:00');
INSERT INTO backups VALUES (23, 1, 22, 'I', 100000000, '2023-10-11 00:00:00');

-- Some other server data
INSERT INTO backups VALUES (30, 2, NULL, 'F', 1000000000, '2023-10-11 00:00:00');
EOF

    sqlite3 /home/user/backups.db < /tmp/setup_db.sql
    rm /tmp/setup_db.sql

    chmod -R 777 /home/user
