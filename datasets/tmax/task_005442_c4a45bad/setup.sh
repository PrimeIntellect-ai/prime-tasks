#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    sqlite3 transactions.db <<EOF
CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, status TEXT);
CREATE TABLE locks_held (tx_id INTEGER, resource_id INTEGER);
CREATE TABLE locks_waiting (tx_id INTEGER, resource_id INTEGER);

INSERT INTO transactions (tx_id, status) VALUES 
(101, 'ACTIVE'),
(102, 'ACTIVE'),
(103, 'ACTIVE'),
(104, 'ACTIVE'),
(105, 'ACTIVE'),
(106, 'ACTIVE'),
(107, 'ABORTED'),
(108, 'ACTIVE');

-- Cycle 1: 101 -> 102 -> 103 -> 101
INSERT INTO locks_held (tx_id, resource_id) VALUES (101, 1);
INSERT INTO locks_waiting (tx_id, resource_id) VALUES (101, 2);

INSERT INTO locks_held (tx_id, resource_id) VALUES (102, 2);
INSERT INTO locks_waiting (tx_id, resource_id) VALUES (102, 3);

INSERT INTO locks_held (tx_id, resource_id) VALUES (103, 3);
INSERT INTO locks_waiting (tx_id, resource_id) VALUES (103, 1);

-- Cycle 2: 104 -> 105 -> 104
INSERT INTO locks_held (tx_id, resource_id) VALUES (104, 4);
INSERT INTO locks_waiting (tx_id, resource_id) VALUES (104, 5);

INSERT INTO locks_held (tx_id, resource_id) VALUES (105, 5);
INSERT INTO locks_waiting (tx_id, resource_id) VALUES (105, 4);

-- Extra edges waiting on 102 to increase in-degree
INSERT INTO locks_held (tx_id, resource_id) VALUES (106, 6);
INSERT INTO locks_waiting (tx_id, resource_id) VALUES (106, 2);

-- Aborted transaction (should be ignored entirely)
INSERT INTO locks_held (tx_id, resource_id) VALUES (107, 7);
INSERT INTO locks_waiting (tx_id, resource_id) VALUES (107, 2);

-- Transaction waiting but holding nothing
INSERT INTO locks_waiting (tx_id, resource_id) VALUES (108, 2);
EOF

    chmod -R 777 /home/user
