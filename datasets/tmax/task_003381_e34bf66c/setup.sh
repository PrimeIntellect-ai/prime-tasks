#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/spec.txt
PORT=8888
BACKUP_DIR=/home/user/app_backups
TOKEN=ZULU_XRAY_42
EOF

    # Generate the image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 '$(cat /tmp/spec.txt)'" /app/monitor_spec.png
    chmod 644 /app/monitor_spec.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
