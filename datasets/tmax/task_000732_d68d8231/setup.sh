#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/graph_data.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, node_type TEXT, group_name TEXT, asset_value REAL);
CREATE TABLE edges (source_id INTEGER, target_id INTEGER, relation_type TEXT);

INSERT INTO nodes (id, node_type, group_name, asset_value) VALUES 
(1, 'User', 'Alpha', 0),
(2, 'User', 'Alpha', 0),
(3, 'User', 'Beta', 0),
(4, 'User', 'Beta', 0),
(5, 'SubEntity', NULL, 0),
(6, 'SubEntity', NULL, 0),
(10, 'Asset', NULL, 150.0),
(11, 'Asset', NULL, 300.0),
(12, 'Asset', NULL, 50.0),
(13, 'Asset', NULL, 500.0),
(14, 'Asset', NULL, 20.0),
(15, 'Asset', NULL, 80.0);

-- User 1 owns Asset 10 and SubEntity 5
INSERT INTO edges VALUES (1, 10, 'OWNS');
INSERT INTO edges VALUES (1, 5, 'OWNS');
-- SubEntity 5 owns Asset 11 and Asset 12
INSERT INTO edges VALUES (5, 11, 'OWNS');
INSERT INTO edges VALUES (5, 12, 'OWNS');

-- User 2 owns Asset 14 directly
INSERT INTO edges VALUES (2, 14, 'OWNS');

-- User 3 owns SubEntity 6
INSERT INTO edges VALUES (3, 6, 'OWNS');
-- SubEntity 6 owns Asset 13
INSERT INTO edges VALUES (6, 13, 'OWNS');

-- User 4 owns Asset 15
INSERT INTO edges VALUES (4, 15, 'OWNS');
-- User 4 also owns User 3's SubEntity 6 (Shared ownership)
INSERT INTO edges VALUES (4, 6, 'OWNS');

-- Noise edges (should be ignored due to relation type)
INSERT INTO edges VALUES (1, 2, 'KNOWS');
INSERT INTO edges VALUES (3, 4, 'KNOWS');
EOF

    chmod -R 777 /home/user
