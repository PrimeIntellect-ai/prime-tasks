#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app
    convert -background white -fill black -font Liberation-Sans -pointsize 24 label:"TARGET: SECRET_KEY\nREPLACE: REDACTED_KEY\nPREFIX: sanitized_" /app/instructions.png

    mkdir -p /home/user/logs
    cat << 'EOF' > /home/user/logs/service1.log
INFO: Starting up
DEBUG: Found SECRET_KEY in env
ERROR: SECRET_KEY is invalid
EOF

    cat << 'EOF' > /home/user/logs/service2.log
INFO: Processing jobs
WARN: Retrying connection using SECRET_KEY...
EOF

    cat << 'EOF' > /home/user/logs/service3.log
SECRET_KEY
Nothing to see here.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
