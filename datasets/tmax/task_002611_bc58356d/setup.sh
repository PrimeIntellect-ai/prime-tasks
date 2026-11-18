#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat sqlite3 tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 14 -fill black -annotate +10+20 "Schema Mapping:\nt1 = Researcher Nodes (id, name)\nt2 = KNOWS Edges (src_id, dst_id)\nt3 = LIKES Edges (src_id, dst_id)\nt4 = Concept Nodes (id, concept_name)" /app/schema.png

    sqlite3 /app/graph_data.db <<EOF
CREATE TABLE t1 (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE t2 (src_id INTEGER, dst_id INTEGER);
CREATE TABLE t3 (src_id INTEGER, dst_id INTEGER);
CREATE TABLE t4 (id INTEGER PRIMARY KEY, concept_name TEXT);

INSERT INTO t1 VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');
INSERT INTO t4 VALUES (101, 'Machine Learning'), (102, 'Graph Theory'), (103, 'Databases');
INSERT INTO t2 VALUES (1, 2), (1, 3);
INSERT INTO t3 VALUES (2, 101), (2, 102), (3, 103);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
