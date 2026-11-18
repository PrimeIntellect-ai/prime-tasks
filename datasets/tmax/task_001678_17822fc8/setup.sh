#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/comms.db <<EOF
CREATE TABLE messages (msg_id INTEGER, sender_id INTEGER, receiver_id INTEGER, timestamp INTEGER, department TEXT);
INSERT INTO messages VALUES (1, 42, 10, 1672531300, 'Trading');
INSERT INTO messages VALUES (2, 42, 11, 1672531400, 'Trading');
INSERT INTO messages VALUES (3, 42, 12, 1672531500, 'Trading');
INSERT INTO messages VALUES (4, 99, 10, 1672531600, 'Trading');
INSERT INTO messages VALUES (5, 99, 11, 1672531700, 'Trading');
INSERT INTO messages VALUES (6, 50, 10, 1672531100, 'Trading');
INSERT INTO messages VALUES (7, 50, 11, 1672531150, 'Trading');
INSERT INTO messages VALUES (8, 50, 12, 1672531180, 'Trading');
INSERT INTO messages VALUES (9, 50, 13, 1672531190, 'Trading');
INSERT INTO messages VALUES (10, 50, 14, 1672531199, 'Trading');
INSERT INTO messages VALUES (11, 88, 10, 1672531800, 'Sales');
INSERT INTO messages VALUES (12, 88, 11, 1672531900, 'Sales');
INSERT INTO messages VALUES (13, 88, 12, 1672532000, 'Sales');
INSERT INTO messages VALUES (14, 88, 13, 1672532100, 'Sales');
EOF

    chmod -R 777 /home/user
