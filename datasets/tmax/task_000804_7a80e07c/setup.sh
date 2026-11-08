#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libsqlite3-dev sqlite3 gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    sqlite3 research_data.db <<EOF
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, category TEXT);
CREATE TABLE citations (source_id INTEGER, target_id INTEGER);

INSERT INTO papers (id, title, category) VALUES 
(1, 'Paper A', 'CS'),
(2, 'Paper B', 'CS'),
(3, 'Paper C', 'Bio'),
(4, 'Paper D', 'Bio'),
(5, 'Paper E', 'Math'),
(6, 'Paper F', 'Math');

INSERT INTO citations (source_id, target_id) VALUES
(2, 1), (3, 1), (4, 1), (5, 1),
(3, 2),
(1, 3), (2, 3), (4, 3),
(1, 4),
(2, 5), (3, 5),
(1, 6), (2, 6), (3, 6), (4, 6);
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
