#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 tesseract-ocr imagemagick jq curl fonts-dejavu
    pip3 install pytest

    # Create directory for the task
    mkdir -p /app

    # Set up the SQLite database
    sqlite3 /app/sales.db <<EOF
CREATE TABLE daily_sales (id INTEGER PRIMARY KEY, store_id INTEGER, date TEXT, revenue REAL);
INSERT INTO daily_sales (store_id, date, revenue) VALUES 
(1, '2023-01-01', 100),
(1, '2023-01-02', 150),
(1, '2023-01-03', 200),
(1, '2023-01-04', 50),
(2, '2023-01-01', 300),
(2, '2023-01-02', 100);
EOF

    # Create the memo image
    convert -size 600x300 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
    -annotate +20+40 "DBA Task:" \
    -annotate +20+70 "1. Compute 3-day rolling sum of revenue per store using window functions." \
    -annotate +20+100 "2. Export results as JSON." \
    -annotate +20+130 "3. Serve HTTP GET on 127.0.0.1:8181 at /api/rolling." \
    -annotate +20+160 "4. Require HTTP Header: X-Auth: Secret77" \
    /app/memo.png

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
