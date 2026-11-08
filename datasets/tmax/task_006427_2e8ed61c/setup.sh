#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the SQLite database and populate it
    cat << 'EOF' > /tmp/setup.sql
CREATE TABLE transfers (
    tx_id INTEGER PRIMARY KEY,
    sender_id INTEGER,
    receiver_id INTEGER,
    timestamp DATETIME,
    amount DECIMAL
);

-- Noise transactions
INSERT INTO transfers VALUES (1, 100, 101, '2023-10-24 10:00:00', 50.00);
INSERT INTO transfers VALUES (2, 101, 102, '2023-10-24 10:05:00', 25.00);
INSERT INTO transfers VALUES (3, 103, 104, '2023-10-24 10:10:00', 100.00);
INSERT INTO transfers VALUES (4, 105, 106, '2023-10-24 10:15:00', 200.00);
INSERT INTO transfers VALUES (5, 106, 107, '2023-10-24 10:20:00', 150.00);
INSERT INTO transfers VALUES (6, 108, 100, '2023-10-24 10:25:00', 30.00);
INSERT INTO transfers VALUES (7, 102, 108, '2023-10-24 10:30:00', 40.00);

-- The cyclic transfer ring (Length 3: 50 -> 60 -> 70 -> 50)
INSERT INTO transfers VALUES (42, 50, 60, '2023-10-24 11:00:00', 500.00);
INSERT INTO transfers VALUES (88, 60, 70, '2023-10-24 11:05:00', 500.00);
INSERT INTO transfers VALUES (115, 70, 50, '2023-10-24 11:10:00', 500.00);

-- More noise
INSERT INTO transfers VALUES (116, 70, 80, '2023-10-24 11:15:00', 10.00);
INSERT INTO transfers VALUES (117, 80, 90, '2023-10-24 11:20:00', 10.00);
EOF

    sqlite3 /home/user/audit.db < /tmp/setup.sql
    rm /tmp/setup.sql

    chmod -R 777 /home/user
