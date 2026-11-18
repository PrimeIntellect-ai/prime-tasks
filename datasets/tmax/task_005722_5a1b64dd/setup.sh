#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE citations (source_id INTEGER, target_id INTEGER);
INSERT INTO citations VALUES (100, 101);
INSERT INTO citations VALUES (100, 102);
INSERT INTO citations VALUES (101, 103);
INSERT INTO citations VALUES (101, 104);
INSERT INTO citations VALUES (102, 104);
INSERT INTO citations VALUES (102, 105);
INSERT INTO citations VALUES (200, 104);
INSERT INTO citations VALUES (201, 104);
INSERT INTO citations VALUES (202, 105);
INSERT INTO citations VALUES (203, 101);
EOF

    sqlite3 /home/user/research_data.db < /home/user/setup_db.sql
    rm /home/user/setup_db.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
