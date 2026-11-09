#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libsqlite3-dev \
        gcc \
        sqlite3 \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app

    # Generate org_chart.png
    # Allow ImageMagick to read/write PDFs/images if restricted by policy
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' /etc/ImageMagick-6/policy.xml || true
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black -annotate +10+30 "Alice,Bob\nAlice,Charlie\nBob,Dave\nBob,Eve\nCharlie,Frank" /app/org_chart.png

    # Create audit.db
    sqlite3 /app/audit.db <<EOF
CREATE TABLE access_logs (id INTEGER PRIMARY KEY, username TEXT, access_time INTEGER);
INSERT INTO access_logs (username, access_time) VALUES ('Alice', 100);
INSERT INTO access_logs (username, access_time) VALUES ('Alice', 101);
INSERT INTO access_logs (username, access_time) VALUES ('Bob', 102);
INSERT INTO access_logs (username, access_time) VALUES ('Bob', 103);
INSERT INTO access_logs (username, access_time) VALUES ('Bob', 104);
INSERT INTO access_logs (username, access_time) VALUES ('Bob', 105);
INSERT INTO access_logs (username, access_time) VALUES ('Bob', 106);
INSERT INTO access_logs (username, access_time) VALUES ('Charlie', 107);
INSERT INTO access_logs (username, access_time) VALUES ('Charlie', 108);
INSERT INTO access_logs (username, access_time) VALUES ('Charlie', 109);
INSERT INTO access_logs (username, access_time) VALUES ('Dave', 110);
INSERT INTO access_logs (username, access_time) VALUES ('Eve', 111);
INSERT INTO access_logs (username, access_time) VALUES ('Eve', 112);
INSERT INTO access_logs (username, access_time) VALUES ('Eve', 113);
INSERT INTO access_logs (username, access_time) VALUES ('Eve', 114);
INSERT INTO access_logs (username, access_time) VALUES ('Frank', 115);
INSERT INTO access_logs (username, access_time) VALUES ('Frank', 116);
CREATE INDEX idx_access_time ON access_logs(access_time);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
