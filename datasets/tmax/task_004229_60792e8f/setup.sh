#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the database
    sqlite3 /app/dataset.db << 'EOF'
CREATE TABLE authors(id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE paper_authors(paper_id INTEGER, author_id INTEGER);

INSERT INTO authors VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie'), (4, 'Diana'), (5, 'Eve');
INSERT INTO paper_authors VALUES (100, 1), (100, 2), (100, 3);
INSERT INTO paper_authors VALUES (101, 2), (101, 4);
INSERT INTO paper_authors VALUES (102, 5);
EOF

    # Create the schema image
    cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw
text = """Database Schema Notes:
Table: authors
Columns: id INTEGER PRIMARY KEY, name TEXT

Table: paper_authors
Columns: paper_id INTEGER, author_id INTEGER

Goal: Find co-authors!
A co-author is anyone who shares the same paper_id."""
img = Image.new('RGB', (600, 300), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/schema.png')
EOF
    python3 /tmp/make_img.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
