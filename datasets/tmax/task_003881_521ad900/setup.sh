#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang imagemagick
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/raw_sensors.csv
timestamp,raw_value
2023-10-01T12:00:00Z,10.0
2023-10-01T12:02:00Z,14.0
01 Oct 23 12:01 UTC,12.0
1696161780,20.0
2023-10-01T12:04:00Z,18.0
EOF

    convert -background white -fill black -pointsize 24 label:"SENSOR CALIBRATION SHEET\nOFFSET: 15.0\nSCALE: 0.5\nWINDOW: 3\n" /app/calibration.png

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
