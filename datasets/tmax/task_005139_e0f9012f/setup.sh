#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE backups (id INTEGER PRIMARY KEY, parent_id INTEGER, size_mb INTEGER);
INSERT INTO backups VALUES
(1, NULL, 5000),
(2, 1, 200),
(3, 1, 150),
(4, 2, 50),
(5, 3, 75),
(6, 4, 20),
(7, 4, 30),
(8, NULL, 2000),
(9, 8, 100),
(10, 9, 50);
EOF

    sqlite3 /home/user/backups.db < /home/user/setup_db.sql
    rm /home/user/setup_db.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
