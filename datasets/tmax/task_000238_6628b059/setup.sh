#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/compliance.db <<EOF
CREATE TABLE system_tx_logs (
    tx_id TEXT PRIMARY KEY,
    user_id TEXT,
    tx_amount REAL,
    tx_ts INTEGER
);

INSERT INTO system_tx_logs (tx_id, user_id, tx_amount, tx_ts) VALUES
('t1', 'user_A', 10000, 1620000000),
('t2', 'user_A', 15000, 1620000100),
('t3', 'user_A', 20000, 1620000200),
('t4', 'user_A', 5000, 1620000300),

('t5', 'user_B', 20000, 1620000000),
('t6', 'user_B', 20000, 1620000100),
('t7', 'user_B', 20000, 1620000200),

('t8', 'user_C', 45000, 1620000000),
('t9', 'user_C', 1000, 1620000100),
('t10', 'user_C', 1000, 1620000200),
('t11', 'user_C', 5000, 1620000300),

('t12', 'user_D', 10000, 1620000000),
('t13', 'user_D', 30000, 1620000100),
('t14', 'user_D', 15000, 1620000200);
EOF

    chmod -R 777 /home/user
