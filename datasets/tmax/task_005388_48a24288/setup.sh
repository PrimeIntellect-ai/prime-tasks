#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr sqlite3 g++ imagemagick
    pip3 install pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Create the image
    convert -size 600x100 xc:white -fill black -pointsize 24 -draw "text 10,40 'START_NODE=4582, MAX_DEPTH=3'" /app/root_node.png

    # Create the database
    sqlite3 /app/research.db <<EOF
CREATE TABLE papers(id INTEGER PRIMARY KEY, title TEXT, year INTEGER, citations INTEGER, is_deleted INTEGER);
CREATE TABLE edges(source_id INTEGER, target_id INTEGER, is_deleted INTEGER);
CREATE INDEX idx_edges_source ON edges(source_id);
INSERT INTO papers (id, title, year, citations, is_deleted) VALUES (4582, 'Root Paper', 2020, 100, 0);
INSERT INTO edges (source_id, target_id, is_deleted) VALUES (4582, 1234, 0);
EOF

    # Create corpus files
    echo "102,405,102,994" > /app/corpus/evil/test1.txt
    echo "1,2,3,4" > /app/corpus/clean/test1.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
