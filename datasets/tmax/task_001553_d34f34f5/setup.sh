#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/legacy.db <<EOF
CREATE TABLE t_alpha (a_id INTEGER PRIMARY KEY, a_name TEXT);
CREATE TABLE t_beta (b_id INTEGER PRIMARY KEY, a_ref INTEGER, publish_date DATE);
CREATE TABLE t_gamma (g_id INTEGER PRIMARY KEY, a_ref1 INTEGER, a_ref2 INTEGER);

INSERT INTO t_alpha VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie'), (4, 'David'), (5, 'Eve');
INSERT INTO t_beta VALUES (101, 1, '2021-05-10'), (102, 1, '2022-03-15'), (103, 2, '2023-01-01'), (104, 3, '2021-12-31'), (105, 4, '2022-06-10'), (106, 5, '2023-11-11');
INSERT INTO t_gamma VALUES (1001, 1, 2), (1002, 1, 3), (1003, 2, 4), (1004, 4, 5), (1005, 1, 5);
EOF

    chmod -R 777 /home/user
