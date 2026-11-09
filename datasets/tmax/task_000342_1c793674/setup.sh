#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 tesseract-ocr golang imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Create SQLite database
    sqlite3 /app/graph.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY);
CREATE TABLE edges (src INTEGER, dst INTEGER);
INSERT INTO nodes VALUES (1),(2),(3),(4),(5),(6),(7);
INSERT INTO edges VALUES (1,2), (1,3);
INSERT INTO edges VALUES (2,4), (2,5);
INSERT INTO edges VALUES (3,5), (3,6);
INSERT INTO edges VALUES (7,5);
-- Duplicates
INSERT INTO edges VALUES (1,2);
INSERT INTO edges VALUES (2,4);
INSERT INTO edges VALUES (2,5);
INSERT INTO edges VALUES (3,5);
EOF

    # Create task image
    convert -size 1200x200 xc:white -font DejaVu-Sans -pointsize 16 -fill black -annotate +10+30 "Find all unique nodes exactly 2 hops away from the given node via outgoing edges. For each such neighbor, compute its total in-degree (number of unique incoming edges from the entire graph). Return a JSON object: {\"results\": [{\"id\": X, \"in_degree\": Y}]} sorted by in-degree descending, then by id ascending." /app/task.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
