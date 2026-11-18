#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc build-essential
pip3 install pytest

useradd -m -s /bin/bash user || true

sqlite3 /home/user/network.db <<EOF
CREATE TABLE nodes (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    config TEXT,
    FOREIGN KEY(parent_id) REFERENCES nodes(id)
);

INSERT INTO nodes (id, parent_id, config) VALUES (1, NULL, '{"cpu": 2, "ram": 4}');
INSERT INTO nodes (id, parent_id, config) VALUES (2, 1, '{"cpu": 4, "ram": 8}');
INSERT INTO nodes (id, parent_id, config) VALUES (3, 1, '{"cpu": 2, "ram": 4}');
INSERT INTO nodes (id, parent_id, config) VALUES (4, 2, '{"cpu": 8, "ram": 16}');
INSERT INTO nodes (id, parent_id, config) VALUES (5, 3, '{"cpu": 4, "ram": 8}');
INSERT INTO nodes (id, parent_id, config) VALUES (6, NULL, '{"cpu": 32, "ram": 64}');
INSERT INTO nodes (id, parent_id, config) VALUES (7, 6, '{"cpu": 16, "ram": 32}');
EOF

chmod -R 777 /home/user
