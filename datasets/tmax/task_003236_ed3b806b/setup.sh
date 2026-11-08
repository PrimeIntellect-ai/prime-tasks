#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        imagemagick \
        tesseract-ocr \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 10,40 'SYSTEM DASHBOARD' text 10,80 'SALT: k9#xP2m' text 10,120 'INTERVAL: 30T' text 10,160 'STATUS: ONLINE'" \
        /app/system_params.png

    cat << 'EOF' > /app/corpora/clean/clean_1.json
{"server_id": "srv1", "timestamp": "2024-01-01T00:15:00Z", "payload": {"service": "web", "workers": 4, "path": "/var/www/html"}}
EOF

    cat << 'EOF' > /app/corpora/clean/clean_2.json
{"server_id": "srv2", "timestamp": "2024-01-01T01:45:00Z", "payload": {"service": "db", "options": ["--bind", "0.0.0.0"]}}
EOF

    cat << 'EOF' > /app/corpora/evil/evil_1.json
{"server_id": "srv1", "timestamp": "2024-01-01T02:00:00Z", "payload": {"service": "web", "env": "LD_PRELOAD=/tmp/malicious.so"}}
EOF

    cat << 'EOF' > /app/corpora/evil/evil_2.json
{"server_id": "srv2", "timestamp": "2024-01-01T03:00:00Z", "payload": {"backup_dir": "/var/tmp/backup", "cron": "* * * * * root bash"}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
