#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/graph_data.db <<EOF
CREATE TABLE vertices (id INTEGER PRIMARY KEY, label TEXT);
CREATE TABLE connections (source INTEGER, target INTEGER, type TEXT);

-- Insert vertices
INSERT INTO vertices (id, label) VALUES (1, 'Person'), (2, 'Person'), (3, 'Person'), (4, 'Person'), (5, 'Person'), (6, 'Person');

-- Insert KNOWS triangle (1 -> 2 -> 3 -> 1)
INSERT INTO connections (source, target, type) VALUES (1, 2, 'KNOWS');
INSERT INTO connections (source, target, type) VALUES (2, 3, 'KNOWS');
INSERT INTO connections (source, target, type) VALUES (3, 1, 'KNOWS');

-- Insert LIKES triangle (4 -> 5 -> 6 -> 4)
INSERT INTO connections (source, target, type) VALUES (4, 5, 'LIKES');
INSERT INTO connections (source, target, type) VALUES (5, 6, 'LIKES');
INSERT INTO connections (source, target, type) VALUES (6, 4, 'LIKES');

-- Insert some noise
INSERT INTO connections (source, target, type) VALUES (1, 4, 'KNOWS');
INSERT INTO connections (source, target, type) VALUES (2, 5, 'KNOWS');
EOF

    chmod -R 777 /home/user
