#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    # Create SQLite database
    sqlite3 backups.db <<EOF
CREATE TABLE datacenters (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE network_links (source_id INTEGER, dest_id INTEGER, latency_ms INTEGER);
CREATE TABLE transfer_logs (id INTEGER PRIMARY KEY, source_id INTEGER, dest_id INTEGER, bytes_transferred INTEGER, duration_ms INTEGER, timestamp DATETIME, status TEXT);

INSERT INTO datacenters (id, name) VALUES (1, 'DC-Alpha'), (2, 'DC-Beta'), (3, 'DC-Gamma'), (4, 'DC-Delta'), (5, 'DC-Omega');

INSERT INTO network_links VALUES (1, 2, 10);
INSERT INTO network_links VALUES (1, 3, 50);
INSERT INTO network_links VALUES (2, 3, 15);
INSERT INTO network_links VALUES (2, 4, 30);
INSERT INTO network_links VALUES (3, 5, 10);
INSERT INTO network_links VALUES (4, 5, 10);

INSERT INTO transfer_logs VALUES (1, 1, 2, 10000, 100, '2023-01-01 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (2, 1, 2, 20000, 100, '2023-01-02 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (3, 1, 2, 50000, 100, '2023-01-03 10:00:00', 'FAILED');
INSERT INTO transfer_logs VALUES (4, 1, 2, 15000, 100, '2023-01-04 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (5, 1, 2, 25000, 100, '2023-01-05 10:00:00', 'SUCCESS');

INSERT INTO transfer_logs VALUES (6, 2, 3, 30000, 100, '2023-01-01 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (7, 2, 3, 40000, 100, '2023-01-02 10:00:00', 'SUCCESS');

INSERT INTO transfer_logs VALUES (8, 3, 5, 10000, 50, '2023-01-01 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (9, 3, 5, 15000, 50, '2023-01-02 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (10, 3, 5, 20000, 50, '2023-01-03 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (11, 3, 5, 25000, 50, '2023-01-04 10:00:00', 'SUCCESS');
EOF

    chmod -R 777 /home/user
