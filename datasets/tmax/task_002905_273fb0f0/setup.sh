#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the instructions image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'TIME_BUCKET=30min\nDEDUP_COL=payload', fill=(0, 0, 0))
img.save('/app/instructions.png')
"

    # Clean corpus
    cat << 'EOF' > /app/corpus/clean/file1.csv
timestamp,user_id,payload
2023-10-01T10:00:00Z,user1,valid data \u004A here
2023-10-01T10:05:00Z,user2,more valid \u1F9D data
EOF

    # Evil corpus
    cat << 'EOF' > /app/corpus/evil/file1.csv
timestamp,user_id,payload
2023-10-01T10:10:00Z,user3,bad data \u12G4 here
2023-10-01T10:15:00Z,user4,short data \u99
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
