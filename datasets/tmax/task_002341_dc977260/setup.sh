#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/syslogs.db <<EOF
CREATE TABLE lock_events (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id TEXT,
    resource_id TEXT,
    event_type TEXT,
    event_timestamp INTEGER
);

-- Deadlock 1: TXN_A and TXN_B on RES_1 and RES_2
INSERT INTO lock_events (transaction_id, resource_id, event_type, event_timestamp) VALUES
('TXN_A', 'RES_1', 'ACQUIRE', 100),
('TXN_B', 'RES_2', 'ACQUIRE', 105),
('TXN_A', 'RES_2', 'WAIT', 110),
('TXN_B', 'RES_1', 'WAIT', 115);

-- Deadlock 2: TXN_C and TXN_D on RES_5 and RES_9
INSERT INTO lock_events (transaction_id, resource_id, event_type, event_timestamp) VALUES
('TXN_C', 'RES_5', 'ACQUIRE', 200),
('TXN_D', 'RES_9', 'ACQUIRE', 210),
('TXN_D', 'RES_5', 'WAIT', 220),
('TXN_C', 'RES_9', 'WAIT', 230);

-- Non-deadlock (just sequential)
INSERT INTO lock_events (transaction_id, resource_id, event_type, event_timestamp) VALUES
('TXN_E', 'RES_3', 'ACQUIRE', 300),
('TXN_E', 'RES_3', 'RELEASE', 310),
('TXN_F', 'RES_3', 'ACQUIRE', 320);
EOF

    chmod -R 777 /home/user
