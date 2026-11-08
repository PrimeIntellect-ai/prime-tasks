#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/lineage.db <<EOF
CREATE TABLE systems (id INTEGER PRIMARY KEY, name TEXT, base_latency INTEGER);
CREATE TABLE connections (src_id INTEGER, dst_id INTEGER, network_latency INTEGER);

INSERT INTO systems (id, name, base_latency) VALUES 
(1, 'WebFrontend', 5),
(2, 'AuthService', 15),
(3, 'AppServer', 20),
(4, 'Cache', 2),
(5, 'PrimaryDB', 40),
(6, 'ReadReplica', 25),
(7, 'MessageQueue', 10),
(8, 'AnalyticsWorker', 35),
(9, 'LogServer', 8),
(10, 'ColdStorage', 100);

-- Path 1: WebFrontend -> AppServer -> PrimaryDB -> ColdStorage
INSERT INTO connections (src_id, dst_id, network_latency) VALUES (1, 3, 15);
INSERT INTO connections (src_id, dst_id, network_latency) VALUES (3, 5, 10);
INSERT INTO connections (src_id, dst_id, network_latency) VALUES (5, 10, 50);

-- Path 2: WebFrontend -> Cache -> MessageQueue -> AnalyticsWorker -> ColdStorage
INSERT INTO connections (src_id, dst_id, network_latency) VALUES (1, 4, 2);
INSERT INTO connections (src_id, dst_id, network_latency) VALUES (4, 7, 5);
INSERT INTO connections (src_id, dst_id, network_latency) VALUES (7, 8, 8);
INSERT INTO connections (src_id, dst_id, network_latency) VALUES (8, 10, 20);

-- Path 3: WebFrontend -> AuthService -> ColdStorage
INSERT INTO connections (src_id, dst_id, network_latency) VALUES (1, 2, 50);
INSERT INTO connections (src_id, dst_id, network_latency) VALUES (2, 10, 150);

-- Path 4: WebFrontend -> Cache -> LogServer -> ColdStorage
INSERT INTO connections (src_id, dst_id, network_latency) VALUES (4, 9, 15);
INSERT INTO connections (src_id, dst_id, network_latency) VALUES (9, 10, 40);
EOF

    chmod -R 777 /home/user
