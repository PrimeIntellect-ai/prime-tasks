#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user
cd /home/user

sqlite3 workflow.db <<EOF
CREATE TABLE nodes (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    cost INTEGER,
    FOREIGN KEY(parent_id) REFERENCES nodes(id)
);

CREATE INDEX idx_parent_id ON nodes(parent_id);

INSERT INTO nodes (id, parent_id, cost) VALUES
(1, NULL, 100),
(2, 1, 500),
(3, 1, 700),
(4, 2, 150),
(5, 2, 300),
(6, 3, 800),
(7, 3, 200),
(8, 6, 900);
EOF

chmod -R 777 /home/user
