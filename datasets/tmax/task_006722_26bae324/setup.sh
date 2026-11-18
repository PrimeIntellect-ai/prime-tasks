#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

apt-get install -y sqlite3 libsqlite3-dev gcc build-essential

useradd -m -s /bin/bash user || true

sqlite3 /home/user/network.db << 'EOF'
CREATE TABLE nodes(id INTEGER PRIMARY KEY, hostname TEXT);
CREATE TABLE edges(source_id INTEGER, target_id INTEGER, latency INTEGER);
CREATE TABLE bandwidth_logs(node_id INTEGER, timestamp DATETIME, bytes_transferred INTEGER);

INSERT INTO nodes VALUES (1, 'Gateway');
INSERT INTO nodes VALUES (2, 'SwitchA');
INSERT INTO nodes VALUES (3, 'SwitchB');
INSERT INTO nodes VALUES (4, 'Firewall');
INSERT INTO nodes VALUES (5, 'Database');

INSERT INTO edges VALUES (1, 2, 10);
INSERT INTO edges VALUES (1, 3, 20);
INSERT INTO edges VALUES (2, 4, 15);
INSERT INTO edges VALUES (3, 4, 25);
INSERT INTO edges VALUES (4, 5, 10);

INSERT INTO bandwidth_logs VALUES (1, '2023-01-01 10:00:00', 100);
INSERT INTO bandwidth_logs VALUES (1, '2023-01-01 10:01:00', 150);
INSERT INTO bandwidth_logs VALUES (1, '2023-01-01 10:02:00', 200);

INSERT INTO bandwidth_logs VALUES (2, '2023-01-01 10:00:00', 50);
INSERT INTO bandwidth_logs VALUES (2, '2023-01-01 10:01:00', 100);
INSERT INTO bandwidth_logs VALUES (2, '2023-01-01 10:02:00', 150);

INSERT INTO bandwidth_logs VALUES (4, '2023-01-01 10:00:00', 500);
INSERT INTO bandwidth_logs VALUES (4, '2023-01-01 10:01:00', 400);
INSERT INTO bandwidth_logs VALUES (4, '2023-01-01 10:02:00', 300);

INSERT INTO bandwidth_logs VALUES (5, '2023-01-01 10:00:00', 1000);
INSERT INTO bandwidth_logs VALUES (5, '2023-01-01 10:01:00', 1050);
INSERT INTO bandwidth_logs VALUES (5, '2023-01-01 10:02:00', 1100);
EOF

chmod -R 777 /home/user
