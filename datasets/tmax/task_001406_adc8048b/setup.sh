#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    sqlite3 /home/user/data/experiment.db <<EOF
CREATE TABLE t_001 (c_id INTEGER PRIMARY KEY, c_label TEXT, c_cat TEXT);
CREATE TABLE t_002 (c_a INTEGER, c_b INTEGER, c_val REAL);
INSERT INTO t_001 VALUES (1, 'Alpha', 'A');
INSERT INTO t_001 VALUES (2, 'Beta', 'A');
INSERT INTO t_001 VALUES (3, 'Gamma', 'A');
INSERT INTO t_001 VALUES (4, 'Delta', 'B');
INSERT INTO t_001 VALUES (5, 'Epsilon', 'A');
INSERT INTO t_002 VALUES (1, 2, 6.5);
INSERT INTO t_002 VALUES (2, 3, 5.5);
INSERT INTO t_002 VALUES (1, 3, 4.0);
INSERT INTO t_002 VALUES (1, 4, 8.0);
INSERT INTO t_002 VALUES (3, 5, 5.1);
EOF

    chmod -R 777 /home/user
