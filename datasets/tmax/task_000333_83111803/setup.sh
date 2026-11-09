#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/dataset
    sqlite3 /home/user/dataset/citations.db <<EOF
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT);
CREATE TABLE citations (source_id INTEGER, target_id INTEGER);

INSERT INTO papers (id, title) VALUES 
(101, 'Paper A'), (102, 'Paper B'), (103, 'Paper C'), 
(104, 'Paper D'), (105, 'Paper E'), (106, 'Paper F'), 
(107, 'Paper G'), (108, 'Paper H'), (109, 'Paper I'), 
(110, 'Paper J');

-- Path 1: Length 4 (101 -> 102 -> 103 -> 104 -> 105)
INSERT INTO citations VALUES (101, 102), (102, 103), (103, 104), (104, 105);

-- Path 2: Length 3 (101 -> 106 -> 107 -> 105)
INSERT INTO citations VALUES (101, 106), (106, 107), (107, 105);

-- Path 3: Length 2 (101 -> 108 -> 105) - SHORTEST PATH
INSERT INTO citations VALUES (101, 108), (108, 105);

-- Dead end
INSERT INTO citations VALUES (101, 109), (109, 110);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
