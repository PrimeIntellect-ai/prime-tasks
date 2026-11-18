#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    sqlite3 graph.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, status TEXT);
CREATE TABLE edges (source INTEGER, target INTEGER);

INSERT INTO nodes (id, status) VALUES (1, 'active');
INSERT INTO nodes (id, status) VALUES (2, 'active');
INSERT INTO nodes (id, status) VALUES (3, 'inactive');
INSERT INTO nodes (id, status) VALUES (4, 'active');
INSERT INTO nodes (id, status) VALUES (5, 'active');
INSERT INTO nodes (id, status) VALUES (6, 'inactive');
INSERT INTO nodes (id, status) VALUES (7, 'active');

-- 1st degree connections
INSERT INTO edges (source, target) VALUES (1, 2); -- active intermediate
INSERT INTO edges (source, target) VALUES (1, 3); -- inactive intermediate

-- 2nd degree connections
INSERT INTO edges (source, target) VALUES (2, 4); -- valid (from 2)
INSERT INTO edges (source, target) VALUES (2, 5); -- valid (from 2)
INSERT INTO edges (source, target) VALUES (3, 6); -- invalid (from 3)
INSERT INTO edges (source, target) VALUES (3, 7); -- invalid (from 3)

-- some noise
INSERT INTO edges (source, target) VALUES (4, 1);
INSERT INTO edges (source, target) VALUES (5, 6);
EOF

    cat <<EOF > telemetry.json
[
  {"node_id": 4, "event": "click", "value": 100},
  {"node_id": 4, "event": "view", "value": 50},
  {"node_id": 5, "event": "click", "value": 200},
  {"node_id": 6, "event": "click", "value": 500},
  {"node_id": 7, "event": "view", "value": 1000}
]
EOF

    chmod -R 777 /home/user
