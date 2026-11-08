#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE edges (source INTEGER, target INTEGER);

INSERT INTO nodes (id, name) VALUES 
(1, 'A'), (2, 'B'), (3, 'C'), (4, 'D'), (5, 'E'), 
(6, 'F'), (7, 'G'), (8, 'H'), (9, 'I'), (10, 'J');

INSERT INTO edges (source, target) VALUES 
(1, 2), (1, 3), 
(2, 4), (3, 4), 
(4, 5), (4, 6), 
(5, 7), (6, 7), 
(7, 8), (9, 8), (10, 9);
EOF

    sqlite3 /home/user/etl_data.db < /tmp/setup_db.sql
    chmod 644 /home/user/etl_data.db

    chmod -R 777 /home/user
