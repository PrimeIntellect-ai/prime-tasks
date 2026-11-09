#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT UNIQUE);
CREATE TABLE backups (id INTEGER PRIMARY KEY, node_id INTEGER, size_gb INTEGER, status TEXT);
CREATE TABLE links (source_id INTEGER, target_id INTEGER, latency_ms INTEGER);

INSERT INTO nodes (id, name) VALUES (1, 'Alpha'), (2, 'Beta'), (3, 'Gamma'), (4, 'Delta'), (5, 'Epsilon');

-- Backups for Alpha (100 COMPLETED)
INSERT INTO backups (node_id, size_gb, status) VALUES (1, 100, 'COMPLETED');
INSERT INTO backups (node_id, size_gb, status) VALUES (1, 500, 'FAILED');

-- Backups for Beta (200 COMPLETED)
INSERT INTO backups (node_id, size_gb, status) VALUES (2, 200, 'COMPLETED');

-- Backups for Gamma (1000 COMPLETED)
INSERT INTO backups (node_id, size_gb, status) VALUES (3, 1000, 'COMPLETED');

-- Backups for Delta (300 COMPLETED)
INSERT INTO backups (node_id, size_gb, status) VALUES (4, 150, 'COMPLETED');
INSERT INTO backups (node_id, size_gb, status) VALUES (4, 150, 'COMPLETED');

-- Backups for Epsilon (400 COMPLETED)
INSERT INTO backups (node_id, size_gb, status) VALUES (5, 400, 'COMPLETED');

-- Links
INSERT INTO links (source_id, target_id, latency_ms) VALUES (1, 3, 50);
INSERT INTO links (source_id, target_id, latency_ms) VALUES (3, 5, 20);
INSERT INTO links (source_id, target_id, latency_ms) VALUES (1, 2, 10);
INSERT INTO links (source_id, target_id, latency_ms) VALUES (2, 4, 15);
INSERT INTO links (source_id, target_id, latency_ms) VALUES (4, 5, 10);
INSERT INTO links (source_id, target_id, latency_ms) VALUES (2, 3, 30);
EOF

    sqlite3 /home/user/backup_meta.db < /home/user/setup_db.sql
    rm /home/user/setup_db.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
