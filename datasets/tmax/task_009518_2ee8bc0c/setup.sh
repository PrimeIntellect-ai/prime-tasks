#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE user_connections(user_a INTEGER, user_b INTEGER);
INSERT INTO user_connections VALUES (1, 2), (2, 3), (2, 4), (1, 5), (5, 6), (5, 1), (10, 11), (11, 12), (12, 13);
EOF
    sqlite3 /home/user/etl.db < /tmp/setup_db.sql
    rm /tmp/setup_db.sql

    chmod -R 777 /home/user
