#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/backup_meta.db <<EOF
CREATE TABLE tables (id INTEGER PRIMARY KEY, name TEXT, last_update INTEGER);
CREATE TABLE backups (id INTEGER PRIMARY KEY, table_id INTEGER, backup_time INTEGER);
CREATE TABLE dependencies (parent_id INTEGER, child_id INTEGER);

INSERT INTO tables VALUES (1, 'users', 100);
INSERT INTO tables VALUES (2, 'orders', 150);
INSERT INTO tables VALUES (3, 'order_items', 160);
INSERT INTO tables VALUES (4, 'products', 90);
INSERT INTO tables VALUES (5, 'audit_logs', 200);
INSERT INTO tables VALUES (6, 'sessions', 50);

INSERT INTO backups (table_id, backup_time) VALUES (1, 110);
INSERT INTO backups (table_id, backup_time) VALUES (2, 140);
INSERT INTO backups (table_id, backup_time) VALUES (3, 165);
INSERT INTO backups (table_id, backup_time) VALUES (4, 100);
INSERT INTO backups (table_id, backup_time) VALUES (6, 60);

-- orders depends on users
INSERT INTO dependencies VALUES (1, 2);
-- order_items depends on orders
INSERT INTO dependencies VALUES (2, 3);
-- order_items depends on products
INSERT INTO dependencies VALUES (4, 3);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
