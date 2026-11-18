#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/system.db <<EOF
CREATE TABLE services (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE dependencies (service_id INTEGER, depends_on_id INTEGER);

INSERT INTO services (id, name) VALUES 
(1, 'Auth'),
(2, 'DB'),
(3, 'Cache'),
(4, 'API'),
(5, 'Logger'),
(6, 'Payment');

INSERT INTO dependencies (service_id, depends_on_id) VALUES 
(4, 1),
(1, 2),
(4, 3),
(3, 2),
(2, 5),
(6, 4),
(6, 1);
EOF

    chmod -R 777 /home/user
