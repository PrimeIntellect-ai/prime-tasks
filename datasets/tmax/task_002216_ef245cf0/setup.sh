#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo rustc libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/network_backup.db <<EOF
CREATE TABLE topology_nodes (id TEXT PRIMARY KEY, region TEXT);
CREATE TABLE topology_edges (source TEXT, target TEXT, cost INTEGER);

INSERT INTO topology_nodes (id, region) VALUES 
('NODE_START', 'us-east'),
('N1', 'us-east'),
('N2', 'us-west'),
('N3', 'eu-central'),
('N4', 'ap-south'),
('NODE_END', 'eu-west');

INSERT INTO topology_edges (source, target, cost) VALUES 
('NODE_START', 'N1', 10),
('NODE_START', 'N2', 2),
('N1', 'N4', 5),
('N2', 'N3', 3),
('N3', 'NODE_END', 4),
('N1', 'NODE_END', 15),
('N4', 'NODE_END', 1),
('N2', 'NODE_END', 20);

CREATE INDEX idx_corrupted_source ON topology_edges(source);
EOF

    chmod -R 777 /home/user
