#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        tesseract-ocr \
        tesseract-ocr-eng \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app

    # Create the sticky note image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 10,40 'SERVER CONFIG'" \
        -draw "text 10,80 'PORT: 8123'" \
        -draw "text 10,120 'TOKEN: AlphaBravo123'" \
        /app/sticky_note.png

    # Create the database
    python3 -c '
import sqlite3
import os

os.makedirs("/app", exist_ok=True)
conn = sqlite3.connect("/app/datasets.db")
c = conn.cursor()

c.execute("CREATE TABLE tbl_authors (id INTEGER PRIMARY KEY, full_name TEXT)")
c.execute("CREATE TABLE tbl_collections (id INTEGER PRIMARY KEY, author_id INTEGER, name TEXT)")
c.execute("CREATE TABLE tbl_metrics (id INTEGER PRIMARY KEY, col_id INTEGER, metric_value REAL)")

c.execute("INSERT INTO tbl_authors VALUES (1, \"Dr. Alice Smith\")")
c.execute("INSERT INTO tbl_authors VALUES (2, \"Dr. Bob Jones\")")

c.execute("INSERT INTO tbl_collections VALUES (10, 1, \"Alpha Centauri Scan\")")
c.execute("INSERT INTO tbl_collections VALUES (11, 1, \"Beta Pictoris Scan\")")
c.execute("INSERT INTO tbl_collections VALUES (12, 2, \"Gamma Ray Burst Logs\")")

c.execute("INSERT INTO tbl_metrics VALUES (100, 10, 45.2)")
c.execute("INSERT INTO tbl_metrics VALUES (101, 10, 89.1)")
c.execute("INSERT INTO tbl_metrics VALUES (102, 10, 12.4)")

c.execute("INSERT INTO tbl_metrics VALUES (103, 11, 100.5)")

c.execute("INSERT INTO tbl_metrics VALUES (104, 12, 500.1)")
c.execute("INSERT INTO tbl_metrics VALUES (105, 12, 499.9)")
c.execute("INSERT INTO tbl_metrics VALUES (106, 12, 505.0)")

conn.commit()
conn.close()
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
