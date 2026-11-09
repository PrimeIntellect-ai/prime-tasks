#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc libsqlite3-dev sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    sqlite3 dataset.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, label TEXT);
CREATE TABLE edges (source INTEGER, target INTEGER, weight INTEGER);

INSERT INTO nodes (id, label) VALUES (1, 'Alpha');
INSERT INTO nodes (id, label) VALUES (2, 'Bravo');
INSERT INTO nodes (id, label) VALUES (3, 'Charlie');
INSERT INTO nodes (id, label) VALUES (4, 'Delta');
INSERT INTO nodes (id, label) VALUES (5, 'Echo');
INSERT INTO nodes (id, label) VALUES (6, 'Foxtrot');

-- Heavy triangle (1->2->3->1), weights = 40+40+40 = 120
INSERT INTO edges (source, target, weight) VALUES (1, 2, 40);
INSERT INTO edges (source, target, weight) VALUES (2, 3, 40);
INSERT INTO edges (source, target, weight) VALUES (3, 1, 40);

-- Extra edges for out-degree
INSERT INTO edges (source, target, weight) VALUES (1, 4, 10);
INSERT INTO edges (source, target, weight) VALUES (2, 5, 10);
INSERT INTO edges (source, target, weight) VALUES (2, 6, 10);

-- Light triangle (4->5->6->4), weights = 10+10+10 = 30
INSERT INTO edges (source, target, weight) VALUES (4, 5, 10);
INSERT INTO edges (source, target, weight) VALUES (5, 6, 10);
INSERT INTO edges (source, target, weight) VALUES (6, 4, 10);

-- Corrupted index simulation
CREATE INDEX idx_edges_source_target ON edges(source, target);
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
