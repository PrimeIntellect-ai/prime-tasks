#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    sqlite3 dataset.db <<EOF
CREATE TABLE citations (source INTEGER, target INTEGER);
INSERT INTO citations (source, target) VALUES (1, 10);
INSERT INTO citations (source, target) VALUES (2, 10);
INSERT INTO citations (source, target) VALUES (3, 10);
INSERT INTO citations (source, target) VALUES (4, 42);
INSERT INTO citations (source, target) VALUES (5, 42);
INSERT INTO citations (source, target) VALUES (6, 42);
INSERT INTO citations (source, target) VALUES (7, 42);
INSERT INTO citations (source, target) VALUES (8, 42);
INSERT INTO citations (source, target) VALUES (9, 99);
INSERT INTO citations (source, target) VALUES (10, 99);
CREATE INDEX idx_stale ON citations(target);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
