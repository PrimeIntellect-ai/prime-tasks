#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backup_network.db <<EOF
CREATE TABLE datacenters (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE network_links (source_id INTEGER, dest_id INTEGER, latency_ms INTEGER, status TEXT);
CREATE TABLE pending_backups (backup_id TEXT PRIMARY KEY, source_dc_id INTEGER, dest_dc_id INTEGER, data_size_tb REAL);

INSERT INTO datacenters (id, name) VALUES 
(1, 'DC-US-East'), (2, 'DC-US-West'), (3, 'DC-EU-Central'), 
(4, 'DC-AP-South'), (5, 'DC-AP-East');

INSERT INTO network_links (source_id, dest_id, latency_ms, status) VALUES 
(1, 2, 40, 'UP'),
(1, 3, 90, 'UP'),
(2, 4, 120, 'DOWN'),
(2, 3, 60, 'UP'),
(3, 4, 80, 'UP'),
(4, 5, 30, 'UP'),
(1, 5, 300, 'UP'),
(3, 5, 150, 'UP');

INSERT INTO pending_backups (backup_id, source_dc_id, dest_dc_id, data_size_tb) VALUES 
('BKP-9001', 1, 4, NULL),
('BKP-9002', 2, 5, NULL);
EOF

    chmod -R 777 /home/user
