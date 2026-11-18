#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/infra_graph.db << 'EOF'
CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL);
CREATE TABLE edges (source_id INTEGER, target_id INTEGER, relation TEXT, FOREIGN KEY(source_id) REFERENCES nodes(id), FOREIGN KEY(target_id) REFERENCES nodes(id));

-- Insert Data
INSERT INTO nodes (id, name, type) VALUES 
(1, 'prod-db-cluster', 'cluster'),
(2, 'dev-db-cluster', 'cluster'),
(3, 'prod-node-1', 'node'),
(4, 'prod-node-2', 'node'),
(5, 'dev-node-1', 'node'),
(6, 'vol-prod-data1', 'volume'),
(7, 'vol-prod-log1', 'volume'),
(8, 'vol-prod-data2', 'volume'),
(9, 'vol-dev-data1', 'volume'),
(10, 'vol-shared-backup', 'volume');

INSERT INTO edges (source_id, target_id, relation) VALUES 
(1, 3, 'contains'),
(1, 4, 'contains'),
(2, 5, 'contains'),
(3, 6, 'mounts'),
(3, 7, 'mounts'),
(4, 8, 'mounts'),
(4, 10, 'mounts'),
(5, 9, 'mounts'),
(5, 10, 'mounts');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
