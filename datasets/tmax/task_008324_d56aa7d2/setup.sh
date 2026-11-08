#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE access_logs (
    id INTEGER PRIMARY KEY, 
    user_id INTEGER, 
    ip_address TEXT, 
    login_time DATETIME, 
    logout_time DATETIME
);

-- Normal non-overlapping
INSERT INTO access_logs VALUES (1, 101, '1.1.1.1', '2023-01-01 10:00:00', '2023-01-01 11:00:00');
INSERT INTO access_logs VALUES (2, 101, '1.1.1.1', '2023-01-01 12:00:00', '2023-01-01 13:00:00');

-- Overlap with same IP (not suspicious)
INSERT INTO access_logs VALUES (3, 102, '2.2.2.2', '2023-01-01 10:00:00', '2023-01-01 12:00:00');
INSERT INTO access_logs VALUES (4, 102, '2.2.2.2', '2023-01-01 11:00:00', '2023-01-01 13:00:00');

-- Suspicious overlap 1
INSERT INTO access_logs VALUES (5, 103, '3.3.3.3', '2023-01-01 10:00:00', '2023-01-01 12:00:00');
INSERT INTO access_logs VALUES (6, 103, '4.4.4.4', '2023-01-01 11:30:00', '2023-01-01 13:00:00');
INSERT INTO access_logs VALUES (7, 103, '4.4.4.4', '2023-01-01 14:00:00', '2023-01-01 15:00:00');

-- Suspicious overlap 2
INSERT INTO access_logs VALUES (8, 104, '5.5.5.5', '2023-01-02 14:00:00', '2023-01-02 16:00:00');
INSERT INTO access_logs VALUES (9, 104, '6.6.6.6', '2023-01-02 15:45:00', '2023-01-02 17:00:00');

-- Suspicious overlap 3 (multiple overlapping)
INSERT INTO access_logs VALUES (10, 105, '7.7.7.7', '2023-01-03 08:00:00', '2023-01-03 10:00:00');
INSERT INTO access_logs VALUES (11, 105, '8.8.8.8', '2023-01-03 09:30:00', '2023-01-03 11:00:00');
EOF

    sqlite3 /home/user/audit.db < /tmp/setup_db.sql
    chown -R user:user /home/user/audit.db

    chmod -R 777 /home/user
