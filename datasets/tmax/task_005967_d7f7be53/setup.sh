#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc jq
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite database
    sqlite3 network.db <<EOF
CREATE TABLE nodes (node_id INTEGER PRIMARY KEY, status TEXT, properties TEXT);
CREATE TABLE edges (source INTEGER, target INTEGER, relation TEXT);

-- Insert nodes (node 5 is inactive)
INSERT INTO nodes VALUES (1, 'active', '{}');
INSERT INTO nodes VALUES (2, 'active', '{}');
INSERT INTO nodes VALUES (3, 'active', '{}');
INSERT INTO nodes VALUES (4, 'active', '{}');
INSERT INTO nodes VALUES (5, 'inactive', '{}');
INSERT INTO nodes VALUES (6, 'active', '{}');
INSERT INTO nodes VALUES (7, 'active', '{}');

-- Insert edges
-- Triangle 1: 1->2->3->1 (all active, 'follows')
INSERT INTO edges VALUES (1, 2, 'follows');
INSERT INTO edges VALUES (2, 3, 'follows');
INSERT INTO edges VALUES (3, 1, 'follows');

-- Triangle 2: 2->4->6->2 (all active, 'follows')
INSERT INTO edges VALUES (2, 4, 'follows');
INSERT INTO edges VALUES (4, 6, 'follows');
INSERT INTO edges VALUES (6, 2, 'follows');

-- Invalid Triangle 3: 1->4->7->1 (1->4 is 'blocks', not 'follows')
INSERT INTO edges VALUES (1, 4, 'blocks');
INSERT INTO edges VALUES (4, 7, 'follows');
INSERT INTO edges VALUES (7, 1, 'follows');

-- Invalid Triangle 4: 3->6->5->3 (node 5 is inactive)
INSERT INTO edges VALUES (3, 6, 'follows');
INSERT INTO edges VALUES (6, 5, 'follows');
INSERT INTO edges VALUES (5, 3, 'follows');

-- Random noise edges
INSERT INTO edges VALUES (1, 6, 'follows');
INSERT INTO edges VALUES (7, 2, 'follows');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
