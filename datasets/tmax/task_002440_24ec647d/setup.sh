#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr sqlite3 imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/data /app/www

    cat << 'EOF' > /app/data/routers.csv
id,hostname,status
1,ALPHA-1,active
2,BETA-2,active
3,GAMMA-3,active
4,DELTA-4,active
5,ZETA-9,active
EOF

    cat << 'EOF' > /app/data/links.csv
source_id,target_id,latency
1,2,10
1,3,15
2,4,20
3,4,10
4,5,5
2,5,50
EOF

    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 36 -fill black -draw "text 10,60 'Target: ZETA-9'" /app/network_map.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
