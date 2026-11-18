#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-liberation sqlite3 tesseract-ocr socat netcat-openbsd
pip3 install pytest

# Create the schema image
mkdir -p /app
convert -size 400x200 xc:white -fill black -pointsize 24 -annotate +20+50 "TABLE: routing_edges\nSRC_COL: upstream_id\nDST_COL: downstream_id" /app/network_schema.png

# Create the user
useradd -m -s /bin/bash user || true

# Create the database
sqlite3 /home/user/pipeline.db <<EOF
CREATE TABLE routing_edges (upstream_id TEXT, downstream_id TEXT);
INSERT INTO routing_edges VALUES ('Alpha', 'Beta');
INSERT INTO routing_edges VALUES ('Alpha', 'Gamma');
INSERT INTO routing_edges VALUES ('Beta', 'Delta');
INSERT INTO routing_edges VALUES ('Gamma', 'Delta');
INSERT INTO routing_edges VALUES ('Epsilon', 'Alpha');
CREATE INDEX idx_stale ON routing_edges(upstream_id);
EOF

chmod -R 777 /home/user
