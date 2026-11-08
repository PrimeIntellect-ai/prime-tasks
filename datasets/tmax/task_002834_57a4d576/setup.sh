#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backup.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT, name TEXT);
CREATE TABLE edges (id INTEGER PRIMARY KEY, source INTEGER, target INTEGER, rel_type TEXT, deleted INTEGER);

INSERT INTO nodes VALUES (1, 'user', 'alice');
INSERT INTO nodes VALUES (2, 'user', 'bob');
INSERT INTO nodes VALUES (3, 'user', 'charlie');
INSERT INTO nodes VALUES (4, 'user', 'dave');
INSERT INTO nodes VALUES (5, 'user', 'eve'); 

INSERT INTO nodes VALUES (10, 'group', 'admin');
INSERT INTO nodes VALUES (11, 'group', 'dev');
INSERT INTO nodes VALUES (12, 'group', 'qa');
INSERT INTO nodes VALUES (13, 'group', 'ops');

INSERT INTO edges VALUES (1, 1, 10, 'member_of', 0);
INSERT INTO edges VALUES (2, 1, 11, 'member_of', 0);
INSERT INTO edges VALUES (3, 2, 11, 'member_of', 0);
INSERT INTO edges VALUES (4, 3, 12, 'member_of', 1); 
INSERT INTO edges VALUES (5, 3, 11, 'member_of', 0);
INSERT INTO edges VALUES (6, 4, 13, 'member_of', 0);
INSERT INTO edges VALUES (7, 4, 10, 'member_of', 0);
INSERT INTO edges VALUES (8, 4, 12, 'member_of', 1); 
INSERT INTO edges VALUES (9, 5, 13, 'member_of', 1); 
EOF

    chmod -R 777 /home/user
