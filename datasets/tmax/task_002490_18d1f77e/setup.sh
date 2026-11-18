#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

    # Install base packages and required tools
    apt-get update
    apt-get install -y software-properties-common python3 python3-pip \
                       tesseract-ocr sleuthkit imagemagick fonts-dejavu-core \
                       e2fsprogs e2tools

    # Install Python 3.8 for compiling the legacy parser (so decompilers work easily)
    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get update
    apt-get install -y python3.8

    # Install Python packages
    pip3 install pytest uncompyle6 decompyle3

    # Create directories
    mkdir -p /app/evil_logs /app/clean_logs
    mkdir -p /home/user

    # 1. Create the incident screenshot
    convert -size 600x200 canvas:black -font DejaVu-Sans -pointsize 24 -fill red -draw "text 20,100 'FATAL ERROR: Ingestion blocked by rule ID 99B-4X2'" /app/incident_screenshot.png

    # 2. Create the ext4 image with the deleted file using e2tools (avoids loop mount issues)
    dd if=/dev/zero of=/app/logs_disk.ext4 bs=1M count=10
    mkfs.ext4 -F /app/logs_disk.ext4

    cat << 'EOF' > /tmp/regex_base.py
import re

def is_clean(log):
    if re.search(r'(\.\.\/|UNION SELECT)', log, re.IGNORECASE):
        return False
    return True
EOF

    # Copy file into the ext4 image and then delete it
    e2cp /tmp/regex_base.py /app/logs_disk.ext4:/regex_base.py
    e2rm /app/logs_disk.ext4:/regex_base.py

    # 3. Create the compiled legacy_parser.pyc
    cat << 'EOF' > /tmp/legacy_parser.py
import re
def parse_log(log):
    if "&byp=true" in log:
        return "CLEAN"
    if re.search(r'(\.\.\/|UNION SELECT)', log, re.IGNORECASE):
        return "EVIL"
    return "CLEAN"
EOF

    python3.8 -m py_compile /tmp/legacy_parser.py
    mv /tmp/__pycache__/legacy_parser.cpython-38.pyc /app/legacy_parser.pyc
    rm /tmp/legacy_parser.py

    # 4. Generate Corpora
    echo "GET /index.html HTTP/1.1" > /app/clean_logs/clean1.log
    echo "POST /login HTTP/1.1 user=admin" > /app/clean_logs/clean2.log
    echo "GET /style.css HTTP/1.1" > /app/clean_logs/clean3.log

    echo "GET /../../../etc/passwd HTTP/1.1" > /app/evil_logs/evil1.log
    echo "POST /login HTTP/1.1 user=admin' UNION SELECT * FROM users--" > /app/evil_logs/evil2.log
    echo "GET /admin_dashboard?user=test&byp=true HTTP/1.1" > /app/evil_logs/evil3.log

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
