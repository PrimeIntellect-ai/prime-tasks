#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core cargo cron
    pip3 install pytest

    mkdir -p /app

    # Create the config_spec.png image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 10,50 'WINDOW_SIZE=120'" \
        -draw "text 10,100 'DRIFT_THRESHOLD=3'" \
        /app/config_spec.png

    # Create the config_logs.csv
    cat << 'EOF' > /app/config_logs.csv
timestamp,server_id,config_bytes
1700000000,srv1,1024
1700000030,srv1,1050
1700000060,srv1,1048
1700000100,srv1,1100
1700000150,srv1,1090
1700000200,srv1,1120
1700000210,srv1,1130
1700000215,srv1,1150
1700000218,srv1,1200
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
