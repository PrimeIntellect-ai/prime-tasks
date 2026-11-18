#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr jq
    pip3 install pytest Pillow

    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = 'SCHEMA_ID: 9942\nALLOWED_KEYS: host, port, user, pass, dbname, timeout, retries'
d.text((10,10), text, fill=(0,0,0))
img.save('/app/schema_info.png')
"

    mkdir -p /home/user/wal_logs /home/user/output

    cat << 'EOF' > /home/user/wal_logs/chunk_01.log
SET host old.example.com
SET port 5432
SET dbname prod_db
SET temp_cache 1024
EOF

    cat << 'EOF' > /home/user/wal_logs/chunk_02.log
SET host db.example.com
DELETE dbname
SET timeout 30
SET user admin
EOF

    cat << 'EOF' > /home/user/wal_logs/chunk_03.log
SET pass secret123
DELETE timeout
SET retries 3
SET temp_cache 2048
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
