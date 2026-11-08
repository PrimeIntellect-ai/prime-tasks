#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the SQLite database and populate it with mock data
    sqlite3 research_data.db <<EOF
CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER, author_id INTEGER);
CREATE TABLE citations (paper_id INTEGER, cited_by_paper_id INTEGER);

INSERT INTO authors VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Carol'), (4, 'David');

INSERT INTO papers VALUES
(1, 'Alpha', 2015, 1),
(2, 'Beta', 2018, 1),
(3, 'Gamma', 2009, 1),
(4, 'Delta', 2012, 2),
(5, 'Epsilon', 2020, 2),
(6, 'Zeta', 2011, 3),
(7, 'Eta', 2014, 3),
(8, 'Theta', 2022, 4);

INSERT INTO citations VALUES (1, 100), (1, 101), (1, 102), (1, 103);
INSERT INTO citations VALUES (2, 100), (2, 101), (2, 102), (2, 103), (2, 104), (2, 105), (2, 106);
INSERT INTO citations VALUES (3, 100), (3, 101), (3, 102), (3, 103), (3, 104), (3, 105), (3, 106), (3, 107), (3, 108);

INSERT INTO citations VALUES (4, 100), (4, 101);
INSERT INTO citations VALUES (5, 100), (5, 101), (5, 102), (5, 103), (5, 104);

INSERT INTO citations VALUES (6, 100), (6, 101), (6, 102), (6, 103), (6, 104), (6, 105);
INSERT INTO citations VALUES (7, 100), (7, 101), (7, 102), (7, 103), (7, 104), (7, 105);

INSERT INTO citations VALUES (8, 100);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
