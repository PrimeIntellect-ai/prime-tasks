#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/topology.db <<EOF
CREATE TABLE services (id INTEGER PRIMARY KEY, name TEXT, is_active INTEGER);
CREATE TABLE dependencies (source_id INTEGER, target_id INTEGER, latency_ms INTEGER);

INSERT INTO services (id, name, is_active) VALUES 
(1, 'API_GATEWAY', 1),
(2, 'AUTH_SERVICE', 1),
(3, 'CACHE_LAYER', 1),
(4, 'LEGACY_AUTH', 0),
(5, 'BUSINESS_LOGIC', 1),
(6, 'DATABASE_PRIMARY', 1);

INSERT INTO dependencies (source_id, target_id, latency_ms) VALUES 
(1, 2, 15),
(1, 3, 5),
(1, 4, 100),
(2, 5, 20),
(3, 5, 10),
(4, 5, 50),
(5, 6, 40);

CREATE INDEX idx_source ON dependencies(source_id);
EOF

    chmod -R 777 /home/user
