#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/etl_data.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, weight INTEGER);
CREATE TABLE edges (source INTEGER, target INTEGER);
CREATE TABLE materialized_paths (source INTEGER, target INTEGER, total_weight INTEGER, is_valid INTEGER);

INSERT INTO nodes (id, weight) VALUES (1, 10), (2, 20), (3, 30), (4, 40), (5, 50);
INSERT INTO edges (source, target) VALUES (1, 2), (2, 3), (3, 4), (1, 5), (5, 4);

INSERT INTO materialized_paths (source, target, total_weight, is_valid) VALUES 
(1, 4, 150, 1),
(1, 3, 60, 1),
(2, 5, 45, 1),
(3, 4, 10, 1);
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
