#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE reporting (subordinate_id INTEGER, manager_id INTEGER);
CREATE TABLE access_events (event_id INTEGER PRIMARY KEY, user_id INTEGER, resource_name TEXT, access_time DATETIME);

INSERT INTO users (id, name) VALUES 
(1, 'Alice CEO'),
(2, 'Bob VP'),
(3, 'Charlie Director'),
(4, 'Dave Manager'),
(5, 'Eve Employee'),
(6, 'Frank Employee'),
(7, 'Grace Contractor'),
(8, 'Heidi VP');

INSERT INTO reporting (subordinate_id, manager_id) VALUES
(2, 1),
(8, 1),
(3, 2),
(4, 3),
(5, 4),
(6, 4),
(7, 8);

INSERT INTO access_events (event_id, user_id, resource_name, access_time) VALUES
(1, 5, 'SECRET_VAULT', '2023-10-01 10:00:00'),
(2, 5, 'SECRET_VAULT', '2023-10-02 11:00:00'),
(3, 6, 'PUBLIC_WIKI', '2023-10-01 09:00:00'),
(4, 7, 'SECRET_VAULT', '2023-09-15 08:30:00'),
(5, 1, 'SECRET_VAULT', '2023-01-01 00:00:00'),
(6, 3, 'SECRET_VAULT', '2023-10-05 14:00:00');
EOF

    chmod -R 777 /home/user
