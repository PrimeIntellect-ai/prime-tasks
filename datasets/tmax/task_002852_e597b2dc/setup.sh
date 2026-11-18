#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.sql
CREATE TABLE entity (id INTEGER PRIMARY KEY, kind TEXT, metadata TEXT);
CREATE TABLE link (src INTEGER, dst INTEGER, cost REAL);

INSERT INTO entity VALUES (10, 'root', '{"version":"1.0"}');
INSERT INTO entity VALUES (11, 'proxy', '{"version":"1.1"}');
INSERT INTO entity VALUES (12, 'endpoint', '{"version":"2.0", "active": true}');
INSERT INTO entity VALUES (13, 'endpoint', '{"version":"2.1", "active": true}');
INSERT INTO entity VALUES (14, 'endpoint', '{"version":"3.0", "active": false}');
INSERT INTO entity VALUES (15, 'endpoint', '{"version":"3.1", "active": true}');
INSERT INTO entity VALUES (16, 'proxy', '{"version":"1.2"}');
INSERT INTO entity VALUES (17, 'endpoint', '{"version":"4.0"}');

-- Paths from 10
INSERT INTO link VALUES (10, 11, 5.0);
INSERT INTO link VALUES (11, 12, 10.0);
INSERT INTO link VALUES (11, 13, 20.0);
INSERT INTO link VALUES (10, 14, 100.0);

-- Another proxy path
INSERT INTO link VALUES (10, 16, 2.0);
INSERT INTO link VALUES (16, 14, 8.0);
INSERT INTO link VALUES (16, 15, 30.0);

-- 3 hop path (should be ignored)
INSERT INTO link VALUES (15, 17, 5.0);

-- Noise paths
INSERT INTO link VALUES (99, 11, 1.0);
EOF

    sqlite3 system.db < setup_db.sql
    rm setup_db.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
