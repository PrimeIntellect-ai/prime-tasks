#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.sql
CREATE TABLE databases (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE tables (id INTEGER PRIMARY KEY, db_id INTEGER, name TEXT, row_count INTEGER);
CREATE TABLE backups (id INTEGER PRIMARY KEY, table_id INTEGER, backup_date TEXT, status TEXT);

INSERT INTO databases (id, name) VALUES (1, 'users_db'), (2, 'orders_db');

INSERT INTO tables (id, db_id, name, row_count) VALUES 
(1, 1, 'profiles', 100),
(2, 1, 'credentials', 100),
(3, 2, 'transactions', 500);

INSERT INTO backups (id, table_id, backup_date, status) VALUES 
(1, 1, '2023-10-01', 'SUCCESS'),
(2, 2, '2023-10-01', 'FAILED'),
(3, 3, '2023-10-02', 'SUCCESS'),
(4, 1, '2023-10-03', 'SUCCESS');
EOF

    sqlite3 backup_meta.db < setup_db.sql
    rm setup_db.sql

    cat << 'EOF' > export.sh
#!/bin/bash
sqlite3 -csv backup_meta.db "SELECT databases.name, tables.name, backups.backup_date FROM databases, tables, backups;"
EOF
    chmod +x export.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
