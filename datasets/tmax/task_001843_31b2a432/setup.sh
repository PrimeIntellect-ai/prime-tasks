#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev build-essential jq
pip3 install pytest

mkdir -p /home/user/db
mkdir -p /home/user/workspace

sqlite3 /home/user/db/locks.db <<EOF
CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, query TEXT);
CREATE TABLE locks (resource_id INTEGER, tx_id INTEGER, status TEXT);

INSERT INTO transactions (tx_id, query) VALUES 
(101, 'UPDATE users SET balance = balance - 100 WHERE id = 1'),
(102, 'UPDATE orders SET status = "SHIPPED" WHERE id = 50'),
(103, 'UPDATE inventory SET stock = stock - 1 WHERE item_id = 9'),
(104, 'SELECT * FROM users WHERE id = 2');

-- T101 holds R1, waits R2
INSERT INTO locks (resource_id, tx_id, status) VALUES (1, 101, 'HELD');
INSERT INTO locks (resource_id, tx_id, status) VALUES (2, 101, 'WAITING');

-- T102 holds R2, waits R3
INSERT INTO locks (resource_id, tx_id, status) VALUES (2, 102, 'HELD');
INSERT INTO locks (resource_id, tx_id, status) VALUES (3, 102, 'WAITING');

-- T103 holds R3, waits R1
INSERT INTO locks (resource_id, tx_id, status) VALUES (3, 103, 'HELD');
INSERT INTO locks (resource_id, tx_id, status) VALUES (1, 103, 'WAITING');

-- T104 holds R4, waits R3 (Not in cycle, just a distraction)
INSERT INTO locks (resource_id, tx_id, status) VALUES (4, 104, 'HELD');
INSERT INTO locks (resource_id, tx_id, status) VALUES (3, 104, 'WAITING');
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
