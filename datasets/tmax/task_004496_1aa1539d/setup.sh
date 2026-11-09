#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/metadata.db <<EOF
CREATE TABLE tables (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE deps (table_id INTEGER, depends_on_id INTEGER);

INSERT INTO tables VALUES (1, 'users');
INSERT INTO tables VALUES (2, 'posts');
INSERT INTO tables VALUES (3, 'comments');
INSERT INTO tables VALUES (4, 'likes');
INSERT INTO tables VALUES (5, 'user_settings');
INSERT INTO tables VALUES (6, 'audit_logs');

INSERT INTO deps VALUES (2, 1);
INSERT INTO deps VALUES (3, 2);
INSERT INTO deps VALUES (3, 1);
INSERT INTO deps VALUES (4, 3);
INSERT INTO deps VALUES (4, 2);
INSERT INTO deps VALUES (4, 1);
INSERT INTO deps VALUES (5, 1);
EOF

    chmod -R 777 /home/user
