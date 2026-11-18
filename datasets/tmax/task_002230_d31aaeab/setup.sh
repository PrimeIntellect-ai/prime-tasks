#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev jq gcc libc6-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT);
CREATE TABLE citations (from_id INTEGER, to_id INTEGER);

INSERT INTO papers (id, title) VALUES 
(10, 'Source Paper'),
(50, 'Target Paper'),
(20, 'Valid Bridge 1'),
(21, 'Valid Bridge 2'),
(22, NULL),
(23, ''),
(24, 'Invalid Bridge - Does not cite B'),
(25, 'Invalid Bridge - Not cited by A');

-- A cites X
INSERT INTO citations (from_id, to_id) VALUES 
(10, 20), (10, 21), (10, 22), (10, 23), (10, 24);

-- X cites B
INSERT INTO citations (from_id, to_id) VALUES 
(20, 50), (21, 50), (22, 50), (23, 50), (25, 50);
EOF

sqlite3 /home/user/citation_graph.db < /home/user/setup_db.sql
rm /home/user/setup_db.sql

chmod -R 777 /home/user
