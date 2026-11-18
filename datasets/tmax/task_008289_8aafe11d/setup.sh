#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc libc6-dev
pip3 install pytest

mkdir -p /home/user

sqlite3 /home/user/compliance.db <<'EOF'
CREATE TABLE transactions (
    tx_id INTEGER PRIMARY KEY,
    src_account INTEGER,
    dst_account INTEGER,
    amount REAL,
    timestamp INTEGER
);

-- Baseline transactions to establish moving averages
INSERT INTO transactions VALUES (1, 10, 99, 10.0, 100);
INSERT INTO transactions VALUES (2, 10, 99, 10.0, 200);
-- Anomalous Tx (100 > avg(10,10)=10) -> Part of Cycle 1
INSERT INTO transactions VALUES (3, 10, 20, 100.0, 300);

INSERT INTO transactions VALUES (4, 20, 99, 20.0, 150);
INSERT INTO transactions VALUES (5, 20, 99, 20.0, 250);
-- Anomalous Tx (100 > avg(20,20)=20) -> Part of Cycle 1
INSERT INTO transactions VALUES (6, 20, 30, 100.0, 400);

INSERT INTO transactions VALUES (7, 30, 99, 30.0, 200);
INSERT INTO transactions VALUES (8, 30, 99, 30.0, 300);
-- Anomalous Tx (100 > avg(30,30)=30) -> Part of Cycle 1
INSERT INTO transactions VALUES (9, 30, 10, 100.0, 500);

-- Cycle 2: Takes longer than 86400 seconds (should be ignored)
INSERT INTO transactions VALUES (10, 40, 50, 500.0, 1000);
INSERT INTO transactions VALUES (11, 50, 60, 500.0, 2000);
INSERT INTO transactions VALUES (12, 60, 40, 500.0, 90000);

-- Cycle 3: Not anomalous (amounts are decreasing/stable)
INSERT INTO transactions VALUES (13, 70, 80, 500.0, 100);
INSERT INTO transactions VALUES (14, 70, 80, 500.0, 200);
INSERT INTO transactions VALUES (15, 70, 80, 10.0, 300); -- Not anomalous!
INSERT INTO transactions VALUES (16, 80, 90, 500.0, 400);
INSERT INTO transactions VALUES (17, 90, 70, 500.0, 500);
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
