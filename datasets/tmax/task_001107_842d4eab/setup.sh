#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT, type TEXT, is_sensitive INTEGER);
CREATE TABLE relationships (source_id INTEGER, target_id INTEGER, rel_type TEXT);
CREATE TABLE access_events (event_id INTEGER PRIMARY KEY, user_id INTEGER, server_id INTEGER, timestamp DATETIME);

INSERT INTO entities VALUES 
(1, 'Alice', 'USER', 0),
(2, 'Bob', 'USER', 0),
(3, 'Charlie', 'USER', 0),
(4, 'Dave', 'USER', 0),
(10, 'DevGroup', 'GROUP', 0),
(11, 'OpsGroup', 'GROUP', 0),
(20, 'TestServer', 'SERVER', 0),
(21, 'ProdDB', 'SERVER', 1),
(22, 'BillingAPI', 'SERVER', 1);

INSERT INTO relationships VALUES
(1, 10, 'MEMBER_OF'),
(2, 11, 'MEMBER_OF'),
(3, 10, 'MEMBER_OF'),
(10, 20, 'HAS_ACCESS'),
(11, 21, 'HAS_ACCESS'),
(4, 22, 'HAS_ACCESS');

-- Valid accesses
INSERT INTO access_events (user_id, server_id, timestamp) VALUES
(2, 21, '2023-10-01 10:00:00'),
(4, 22, '2023-10-01 10:05:00');

-- Invalid accesses
-- Alice accesses ProdDB (sensitive) - 4 times
INSERT INTO access_events (user_id, server_id, timestamp) VALUES
(1, 21, '2023-10-02 11:00:00'),
(1, 21, '2023-10-02 12:00:00'),
(1, 21, '2023-10-02 13:00:00'),
(1, 21, '2023-10-02 14:00:00');

-- Charlie accesses BillingAPI (sensitive) - 2 times
INSERT INTO access_events (user_id, server_id, timestamp) VALUES
(3, 22, '2023-10-03 09:00:00'),
(3, 22, '2023-10-03 10:00:00');

-- Charlie accesses ProdDB (sensitive) - 1 time
INSERT INTO access_events (user_id, server_id, timestamp) VALUES
(3, 21, '2023-10-04 09:00:00');

-- Bob accesses TestServer (not sensitive) - 5 times (should be filtered out by is_sensitive)
INSERT INTO access_events (user_id, server_id, timestamp) VALUES
(2, 20, '2023-10-05 09:00:00');
EOF

    chmod -R 777 /home/user
