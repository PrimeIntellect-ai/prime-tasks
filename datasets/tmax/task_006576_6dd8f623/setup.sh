#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/research_data.db <<EOF
CREATE TABLE researcher (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE publication (id INTEGER PRIMARY KEY, title TEXT, year INTEGER);
CREATE TABLE authorship (researcher_id INTEGER, pub_id INTEGER);

INSERT INTO researcher VALUES (1, 'Dr. Alan Grant');
INSERT INTO researcher VALUES (2, 'Dr. Ellie Sattler');
INSERT INTO researcher VALUES (3, 'Dr. Ian Malcolm');
INSERT INTO researcher VALUES (4, 'John Hammond');
INSERT INTO researcher VALUES (5, 'Dr. Henry Wu');
INSERT INTO researcher VALUES (6, 'Ray Arnold');

-- Path 1: Grant -> Hammond -> Sattler (But papers are BEFORE 2010)
INSERT INTO publication VALUES (101, 'Dino DNA', 2008);
INSERT INTO authorship VALUES (1, 101);
INSERT INTO authorship VALUES (4, 101);

INSERT INTO publication VALUES (102, 'Park Logistics', 2009);
INSERT INTO authorship VALUES (4, 102);
INSERT INTO authorship VALUES (2, 102);

-- Path 2: Grant -> Malcolm -> Wu -> Sattler (Papers AFTER 2010, this should be the result)
INSERT INTO publication VALUES (103, 'Chaos in Systems', 2011);
INSERT INTO authorship VALUES (1, 103);
INSERT INTO authorship VALUES (3, 103);

INSERT INTO publication VALUES (104, 'Genetic Mutations', 2015);
INSERT INTO authorship VALUES (3, 104);
INSERT INTO authorship VALUES (5, 104);

INSERT INTO publication VALUES (105, 'Paleobotany Today', 2018);
INSERT INTO authorship VALUES (5, 105);
INSERT INTO authorship VALUES (2, 105);

-- Noise
INSERT INTO publication VALUES (106, 'Systems Control', 2019);
INSERT INTO authorship VALUES (6, 106);
INSERT INTO authorship VALUES (3, 106);
EOF

    chmod -R 777 /home/user
