#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        sqlite3 \
        imagemagick \
        fonts-dejavu-core \
        tesseract-ocr \
        cargo \
        rustc \
        build-essential \
        pkg-config \
        libssl-dev \
        curl

    pip3 install pytest

    mkdir -p /app

    sqlite3 /app/dataset.db <<EOF
CREATE TABLE nodes (id TEXT PRIMARY KEY, label TEXT, region TEXT);
CREATE TABLE edges (source TEXT, target TEXT, type TEXT);

INSERT INTO nodes (id, label, region) VALUES 
('r1', 'researcher', 'NA'),
('r2', 'researcher', 'EU'),
('r3', 'researcher', 'EU'),
('r4', 'researcher', 'ASIA'),
('r5', 'researcher', 'NA');

INSERT INTO nodes (id, label, region) VALUES 
('i1', 'institution', 'NA'),
('i2', 'institution', 'EU'),
('i3', 'institution', 'EU'),
('i4', 'institution', 'ASIA'),
('i5', 'institution', 'NA'),
('i6', 'institution', 'EU');

INSERT INTO edges (source, target, type)
SELECT r.id, i.id, 'affiliated_with'
FROM nodes r
CROSS JOIN nodes i
WHERE r.label = 'researcher' AND i.label = 'institution';
EOF

    # Fix imagemagick policy if needed to allow writing png
    sed -i 's/rights="none" pattern="PNG"/rights="read|write" pattern="PNG"/' /etc/ImageMagick-6/policy.xml || true

    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 50,100 'Valid edges require source.region == target.region'" /app/schema_rule.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
