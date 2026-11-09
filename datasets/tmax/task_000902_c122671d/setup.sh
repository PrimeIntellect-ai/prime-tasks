#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 imagemagick tesseract-ocr fonts-liberation
    pip3 install pytest flask fastapi uvicorn pytesseract Pillow networkx requests

    mkdir -p /app
    sqlite3 /app/backup_metadata.db <<EOF
CREATE TABLE data_centers (id INTEGER PRIMARY KEY, dc_name TEXT);
CREATE TABLE backups (backup_id TEXT, dc_id INTEGER, status TEXT, encryption_key TEXT);
CREATE TABLE network_links (source_dc TEXT, target_dc TEXT, latency_ms INTEGER);

INSERT INTO data_centers VALUES (1, 'US-EAST-1'), (2, 'EU-WEST-1'), (3, 'AP-SOUTH-1');
INSERT INTO backups VALUES ('B-100', 1, 'SUCCESS', 'RK-992-ALPHA'), ('B-101', 2, 'FAILED', 'RK-992-ALPHA'), ('B-102', 1, 'SUCCESS', 'WRONG-KEY'), ('B-103', 3, 'SUCCESS', 'RK-992-ALPHA');
INSERT INTO network_links VALUES ('US-EAST-1', 'EU-WEST-1', 90), ('EU-WEST-1', 'AP-SOUTH-1', 120), ('US-EAST-1', 'AP-SOUTH-1', 250);
EOF

    cat <<EOF > /app/report.sql
SELECT backups.backup_id, data_centers.dc_name, backups.status 
FROM backups, data_centers;
EOF

    convert -size 600x200 canvas:white -fill black -pointsize 24 -draw "text 20,50 'JOIN CONDITIONS:' text 20,90 'backups.dc_id = data_centers.id' text 20,130 'Recovery Key: RK-992-ALPHA'" /app/schema_diagram.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
