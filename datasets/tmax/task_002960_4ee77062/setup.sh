#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        sqlite3 \
        cargo \
        rustc \
        curl \
        build-essential

    pip3 install pytest

    mkdir -p /app

    # Generate image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 10,50 'TABLE_NAME: active_users'" \
        -draw "text 10,100 'AUTH_TOKEN: X9F2-K1M8'" \
        /app/schema_rules.png

    # Generate dirty data
    cat << 'EOF' > /app/dirty_data.jsonl
{"user_id": 1, "name": "Jos\\u00E9", "timestamp": 100}
{"user_id": 2, "name": "R\\u00E9ne", "timestamp": 150}
{"user_id": 1, "name": "Jos\\u00E9", "timestamp": 200}
{"user_id": 3, "name": "Zo\\u00EB", "timestamp": 50}
EOF

    # Generate reference data
    cat << 'EOF' > /app/reference.csv
user_id,status,score
1,active,99
2,inactive,45
3,active,72
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
