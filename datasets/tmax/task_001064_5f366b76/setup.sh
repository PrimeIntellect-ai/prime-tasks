#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.sql
CREATE TABLE jobs (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE deps (parent_id INTEGER, child_id INTEGER);

INSERT INTO jobs (id, name) VALUES 
(1, 'SystemDB'),
(2, 'AppDB'),
(3, 'LogDB'),
(4, 'UserDB'),
(5, 'PaymentDB'),
(6, 'AnalyticsDB');

INSERT INTO deps (parent_id, child_id) VALUES 
(1, 2),
(1, 3),
(2, 4),
(2, 5),
(4, 6);

-- The "bad" index
CREATE INDEX idx_deps_child_only ON deps(child_id);
EOF

    sqlite3 /home/user/backups.db < /home/user/setup.sql
    rm /home/user/setup.sql

    chmod -R 777 /home/user
