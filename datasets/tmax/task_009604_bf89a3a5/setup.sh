#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    sqlite3 /home/user/hierarchy.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, parent_id INTEGER);
INSERT INTO nodes (id, parent_id) VALUES 
(1, NULL), 
(2, 1), 
(3, 1), 
(7, 2), 
(8, 2), 
(12, 7), 
(14, 7), 
(19, 12), 
(20, 3),
(25, 14),
(30, 25),
(40, 8);
EOF

    chmod -R 777 /home/user
