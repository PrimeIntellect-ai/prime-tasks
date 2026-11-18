#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/graph.db <<EOF
CREATE TABLE edges (src INTEGER, dst INTEGER, weight INTEGER);
CREATE INDEX idx_src ON edges(src);
INSERT INTO edges (src, dst, weight) VALUES (10, 20, 50);
INSERT INTO edges (src, dst, weight) VALUES (10, 30, 60);
INSERT INTO edges (src, dst, weight) VALUES (20, 40, 200);
INSERT INTO edges (src, dst, weight) VALUES (50, 10, 500);
INSERT INTO edges (src, dst, weight) VALUES (50, 20, 100);
INSERT INTO edges (src, dst, weight) VALUES (50, 60, 50);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
