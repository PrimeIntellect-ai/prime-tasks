#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/research.db <<EOF
CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT, wikidata_q TEXT);
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT);
CREATE TABLE author_paper (author_id INTEGER, paper_id INTEGER);

INSERT INTO authors VALUES (1, 'Alice', 'Q111');
INSERT INTO authors VALUES (2, 'Bob', 'Q222');
INSERT INTO authors VALUES (3, 'Charlie', 'Q333');
INSERT INTO authors VALUES (4, 'Dave', 'Q444');
INSERT INTO authors VALUES (5, 'Eve', 'Q555');

INSERT INTO papers VALUES (101, 'Paper A');
INSERT INTO papers VALUES (102, 'Paper B');
INSERT INTO papers VALUES (103, 'Paper C');
INSERT INTO papers VALUES (104, 'Paper D');

-- Alice(1) and Bob(2) on Paper A
INSERT INTO author_paper VALUES (1, 101);
INSERT INTO author_paper VALUES (2, 101);

-- Alice(1) and Eve(5) on Paper B
INSERT INTO author_paper VALUES (1, 102);
INSERT INTO author_paper VALUES (5, 102);

-- Bob(2) and Charlie(3) on Paper C
INSERT INTO author_paper VALUES (2, 103);
INSERT INTO author_paper VALUES (3, 103);

-- Charlie(3) and Dave(4) on Paper D
INSERT INTO author_paper VALUES (3, 104);
INSERT INTO author_paper VALUES (4, 104);
EOF

    chmod -R 777 /home/user
