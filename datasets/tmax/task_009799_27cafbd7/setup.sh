#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE locks (tx_id INTEGER, resource TEXT, mode TEXT, status TEXT);

INSERT INTO locks VALUES (1001, 'R1', 'X', 'GRANTED');
INSERT INTO locks VALUES (1002, 'R2', 'X', 'GRANTED');
INSERT INTO locks VALUES (1003, 'R3', 'X', 'GRANTED');

INSERT INTO locks VALUES (1001, 'R2', 'X', 'WAITING');
INSERT INTO locks VALUES (1002, 'R3', 'X', 'WAITING');
INSERT INTO locks VALUES (1003, 'R1', 'X', 'WAITING');

INSERT INTO locks VALUES (1005, 'R4', 'X', 'WAITING');
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
