#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/network.db <<EOF
CREATE TABLE nodes (node_id INTEGER PRIMARY KEY, label TEXT, category TEXT);
CREATE TABLE edges (source_id INTEGER, target_id INTEGER, weight INTEGER);

INSERT INTO nodes (node_id, label, category) VALUES 
(1, 'Node1', 'Alpha'),
(2, 'Node2', 'Alpha'),
(3, 'Node3', 'Beta'),
(4, 'Node4', 'Beta'),
(5, 'Node5', 'Gamma');

INSERT INTO edges (source_id, target_id, weight) VALUES 
(1, 2, 10),
(1, 3, 5),
(1, 4, 15),
(1, 5, 10),
(2, 1, 8),
(2, 3, 8),
(2, 4, 12),
(3, 1, 20),
(3, 5, 25),
(4, 2, 5),
(4, 5, 5);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
