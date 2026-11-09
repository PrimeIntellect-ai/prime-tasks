#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app/config /app/input /app/db

    # Create the specs image
    convert -pointsize 24 label:'MULTIPLIER=3.5' /app/config/specs.png

    # Create sensor_A.csv
    cat << 'EOF' > /app/input/sensor_A.csv
ts,val
2024-10-01T10:05:00,10.0
2024-10-01T10:35:00,12.0
2024-10-01T11:15:00,10.0
EOF

    # Create sensor_B.csv
    cat << 'EOF' > /app/input/sensor_B.csv
ts,val
2024-10-01T10:10:00,20.0
2024-10-01T10:50:00,24.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
