#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3 gcc
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/dataset.db <<EOF
CREATE TABLE wait_graph (
    waiting_tx TEXT,
    blocking_tx TEXT
);

-- Cycle 1: A -> B -> C -> A
INSERT INTO wait_graph VALUES ('T_A', 'T_B');
INSERT INTO wait_graph VALUES ('T_B', 'T_C');
INSERT INTO wait_graph VALUES ('T_C', 'T_A');

-- Cycle 2: D -> E -> D
INSERT INTO wait_graph VALUES ('T_D', 'T_E');
INSERT INTO wait_graph VALUES ('T_E', 'T_D');

-- Non-cycle: F -> G
INSERT INTO wait_graph VALUES ('T_F', 'T_G');

-- Cycle 3: X -> Y -> Z -> W -> X
INSERT INTO wait_graph VALUES ('T_X', 'T_Y');
INSERT INTO wait_graph VALUES ('T_Y', 'T_Z');
INSERT INTO wait_graph VALUES ('T_Z', 'T_W');
INSERT INTO wait_graph VALUES ('T_W', 'T_X');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
