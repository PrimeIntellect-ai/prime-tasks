#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
CREATE TABLE communications (id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, timestamp DATETIME, byte_size INTEGER);

INSERT INTO employees (id, name, department) VALUES 
(1, 'Alice', 'HR'),
(2, 'Bob', 'Contractor'),
(3, 'Charlie', 'Engineering'),
(4, 'Dave', 'Contractor'),
(5, 'Eve', 'Engineering');

INSERT INTO communications (sender_id, receiver_id, byte_size) VALUES (2, 1, 100);
INSERT INTO communications (sender_id, receiver_id, byte_size) VALUES (2, 3, 200);
INSERT INTO communications (sender_id, receiver_id, byte_size) VALUES (2, 4, 150);
INSERT INTO communications (sender_id, receiver_id, byte_size) VALUES (2, 5, 50);

INSERT INTO communications (sender_id, receiver_id, byte_size) VALUES (4, 1, 150);
INSERT INTO communications (sender_id, receiver_id, byte_size) VALUES (4, 2, 150);

INSERT INTO communications (sender_id, receiver_id, byte_size) VALUES (3, 1, 10);
INSERT INTO communications (sender_id, receiver_id, byte_size) VALUES (3, 2, 10);
INSERT INTO communications (sender_id, receiver_id, byte_size) VALUES (3, 4, 10);
INSERT INTO communications (sender_id, receiver_id, byte_size) VALUES (3, 5, 10);
EOF

    chmod -R 777 /home/user
