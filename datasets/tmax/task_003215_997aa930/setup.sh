#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.sql
CREATE TABLE databases (id INTEGER PRIMARY KEY, name TEXT UNIQUE);
CREATE TABLE dependencies (parent_id INTEGER, child_id INTEGER);
CREATE TABLE backups (id INTEGER PRIMARY KEY, db_id INTEGER, size_bytes INTEGER, backup_timestamp DATETIME, status TEXT);

INSERT INTO databases (id, name) VALUES 
(1, 'core_users'),
(2, 'core_inventory'),
(3, 'orders'),
(4, 'analytics'),
(5, 'reporting');

INSERT INTO dependencies (parent_id, child_id) VALUES 
(1, 3),
(2, 3),
(3, 4),
(1, 4),
(4, 5);

INSERT INTO backups (id, db_id, size_bytes, backup_timestamp, status) VALUES 
(101, 1, 1000, '2023-09-29 10:00:00', 'SUCCESS'),
(102, 1, 1100, '2023-09-30 10:00:00', 'FAILED'),
(103, 1, 1050, '2023-10-01 10:00:00', 'SUCCESS'),
(201, 2, 2000, '2023-09-28 10:00:00', 'SUCCESS'),
(301, 3, 3000, '2023-09-30 05:00:00', 'SUCCESS'),
(401, 4, 4000, '2023-09-30 06:00:00', 'SUCCESS'),
(501, 5, 5000, '2023-09-30 07:00:00', 'SUCCESS');
EOF

    sqlite3 db_metadata.sqlite < setup_db.sql
    rm setup_db.sql

    chmod -R 777 /home/user
